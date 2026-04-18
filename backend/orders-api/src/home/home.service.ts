import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';

export type HomeCmsSlide = { id: string; imageUrl: string; title: string };
export type HomeCmsOffer = { id: string; title: string; subtitle?: string; imageUrl: string };

export type HomePublicCmsDto = {
  version: number;
  primarySlider: HomeCmsSlide[];
  offers: HomeCmsOffer[];
  bottomBanner: HomeCmsSlide | null;
};

@Injectable()
export class HomeService {
  private readonly pool: Pool | null;
  private tableReady = false;

  constructor() {
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.HOME_PG_POOL_MAX || 8),
          idleTimeoutMillis: 30_000,
        })
      : null;
    if (this.pool) {
      this.pool.on('connect', (c) => {
        void c.query("SET client_encoding TO 'UTF8'").catch(() => undefined);
      });
    }
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('home database not configured');
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      await this.ensureTable(client);
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private async ensureTable(client: PoolClient): Promise<void> {
    if (this.tableReady) return;
    await client.query(`
      CREATE TABLE IF NOT EXISTS home_sections (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        image TEXT,
        type TEXT NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        sort_order INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_home_sections_active_sort ON home_sections (is_active, sort_order, created_at);
      ALTER TABLE home_sections ADD COLUMN IF NOT EXISTS store_type_id uuid;
      CREATE INDEX IF NOT EXISTS idx_home_sections_store_type ON home_sections (store_type_id, is_active, sort_order, created_at);
      CREATE TABLE IF NOT EXISTS sub_categories (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        home_section_id UUID REFERENCES home_sections(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        image TEXT,
        sort_order INT DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW()
      );
      CREATE TABLE IF NOT EXISTS system_versions (
        key text PRIMARY KEY,
        version bigint NOT NULL DEFAULT 1,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      INSERT INTO system_versions (key, version) VALUES ('home_sections_version', 1)
      ON CONFLICT (key) DO NOTHING;
      CREATE INDEX IF NOT EXISTS idx_sub_categories_section_active_sort
        ON sub_categories (home_section_id, is_active, sort_order, created_at);

      CREATE TABLE IF NOT EXISTS home_cms (
        id smallint PRIMARY KEY,
        slider jsonb NOT NULL DEFAULT '[]'::jsonb,
        offers jsonb NOT NULL DEFAULT '[]'::jsonb,
        bottom_banner jsonb,
        updated_at timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT home_cms_singleton CHECK (id = 1)
      );
      INSERT INTO home_cms (id) VALUES (1) ON CONFLICT DO NOTHING;
      INSERT INTO system_versions (key, version) VALUES ('home_cms_version', 1)
      ON CONFLICT (key) DO NOTHING;
    `);
    this.tableReady = true;
  }

  async getSections(storeTypeId?: string): Promise<{ data: unknown[]; items: unknown[]; version: number }> {
    return this.withClient(async (client) => {
      const sid = storeTypeId?.trim() ?? '';
      const q = sid.length === 0
          ? await client.query(
              `SELECT id::text, name, image, type, store_type_id::text AS "storeTypeId",
                      is_active AS "isActive", sort_order AS "sortOrder", created_at AS "createdAt"
               FROM home_sections
               WHERE is_active = TRUE
               ORDER BY sort_order ASC, created_at ASC`,
            )
          : await client.query(
              `SELECT id::text, name, image, type, store_type_id::text AS "storeTypeId",
                      is_active AS "isActive", sort_order AS "sortOrder", created_at AS "createdAt"
               FROM home_sections
               WHERE is_active = TRUE AND store_type_id = $1::uuid
               ORDER BY sort_order ASC, created_at ASC`,
              [sid],
            );
      const vq = await client.query(
        `SELECT version FROM system_versions WHERE key = 'home_sections_version' LIMIT 1`,
      );
      const version = Number(vq.rows[0]?.['version'] ?? 1);
      return { data: q.rows, items: q.rows, version };
    });
  }

  async getSubCategories(sectionId: string): Promise<{ data: unknown[]; items: unknown[]; version: number }> {
    const sid = sectionId.trim();
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, home_section_id::text AS "home_section_id", name, image,
                sort_order AS "sortOrder", is_active AS "isActive", created_at AS "createdAt"
         FROM sub_categories
         WHERE home_section_id = $1::uuid
           AND is_active = TRUE
         ORDER BY sort_order ASC, created_at ASC`,
        [sid],
      );
      const vq = await client.query(
        `SELECT version FROM system_versions WHERE key = 'home_sections_version' LIMIT 1`,
      );
      const version = Number(vq.rows[0]?.['version'] ?? 1);
      return { data: q.rows, items: q.rows, version };
    });
  }

  /** Hard-coded UTF-8 Arabic defaults when DB row is empty or service runs without DB. */
  static defaultCmsPayload(): Omit<HomePublicCmsDto, 'version'> {
    return {
      primarySlider: [
        {
          id: 's1',
          imageUrl: 'https://picsum.photos/seed/ammarjo-slide1/900/360',
          title: 'تشكيلة جديدة لمواد البناء',
        },
        {
          id: 's2',
          imageUrl: 'https://picsum.photos/seed/ammarjo-slide2/900/360',
          title: 'عروض الصيانة والخدمات',
        },
        {
          id: 's3',
          imageUrl: 'https://picsum.photos/seed/ammarjo-slide3/900/360',
          title: 'توصيل سريع لجميع المحافظات',
        },
      ],
      offers: [
        {
          id: 'o1',
          title: 'خصم 15%',
          subtitle: 'على الطلاء والدهانات',
          imageUrl: 'https://picsum.photos/seed/offer-paint/400/280',
        },
        {
          id: 'o2',
          title: 'قطع غيار',
          subtitle: 'أسعار مخفّضة هذا الأسبوع',
          imageUrl: 'https://picsum.photos/seed/offer-parts/400/280',
        },
        {
          id: 'o3',
          title: 'أدوات كهربائية',
          subtitle: 'ضمان سنة',
          imageUrl: 'https://picsum.photos/seed/offer-tools/400/280',
        },
      ],
      bottomBanner: {
        id: 'b1',
        imageUrl: 'https://picsum.photos/seed/ammarjo-bottom/900/220',
        title: 'حمّل التطبيق وتابع الطلبات لحظة بلحظة',
      },
    };
  }

  private static normalizeSlide(raw: unknown, fallbackId: string): HomeCmsSlide | null {
    if (!raw || typeof raw !== 'object') return null;
    const o = raw as Record<string, unknown>;
    const imageUrl = String(o['imageUrl'] ?? o['image'] ?? '').trim();
    if (!imageUrl) return null;
    const id = String(o['id'] ?? fallbackId).trim() || fallbackId;
    const title = String(o['title'] ?? '').trim();
    return { id, imageUrl, title };
  }

  private static normalizeOffer(raw: unknown, fallbackId: string): HomeCmsOffer | null {
    if (!raw || typeof raw !== 'object') return null;
    const o = raw as Record<string, unknown>;
    const imageUrl = String(o['imageUrl'] ?? o['image'] ?? '').trim();
    if (!imageUrl) return null;
    const id = String(o['id'] ?? fallbackId).trim() || fallbackId;
    const title = String(o['title'] ?? '').trim();
    const subtitle = String(o['subtitle'] ?? '').trim();
    return { id, title, subtitle: subtitle.length > 0 ? subtitle : undefined, imageUrl };
  }

  static mergeCmsFromDb(
    sliderDb: unknown,
    offersDb: unknown,
    bottomDb: unknown,
    version: number,
  ): HomePublicCmsDto {
    const def = HomeService.defaultCmsPayload();
    const sliderIn = Array.isArray(sliderDb) ? sliderDb : [];
    const slides = sliderIn
      .map((r, i) => HomeService.normalizeSlide(r, `s${i + 1}`))
      .filter((x): x is HomeCmsSlide => x != null);
    const offersIn = Array.isArray(offersDb) ? offersDb : [];
    const offers = offersIn
      .map((r, i) => HomeService.normalizeOffer(r, `o${i + 1}`))
      .filter((x): x is HomeCmsOffer => x != null);
    let bottom: HomeCmsSlide | null = null;
    if (bottomDb && typeof bottomDb === 'object') {
      bottom = HomeService.normalizeSlide(bottomDb, 'b1');
    }
    if (!bottom) bottom = def.bottomBanner;

    return {
      version,
      primarySlider: slides.length > 0 ? slides : def.primarySlider,
      offers: offers.length > 0 ? offers : def.offers,
      bottomBanner: bottom ?? def.bottomBanner,
    };
  }

  /**
   * Public home marketing payload (slider, offers strip, bottom banner).
   * Editable from admin `GET|PATCH /admin/rest/home-cms`.
   */
  async getPublicCms(): Promise<HomePublicCmsDto> {
    if (!this.pool) {
      return { version: 1, ...HomeService.defaultCmsPayload() };
    }
    return this.withClient(async (client) => {
      const rowQ = await client.query(`SELECT slider, offers, bottom_banner FROM home_cms WHERE id = 1 LIMIT 1`);
      const vq = await client.query(`SELECT version FROM system_versions WHERE key = 'home_cms_version' LIMIT 1`);
      const version = Number(vq.rows[0]?.['version'] ?? 1);
      const row = rowQ.rows[0] as Record<string, unknown> | undefined;
      if (!row) {
        return { version, ...HomeService.defaultCmsPayload() };
      }
      return HomeService.mergeCmsFromDb(row['slider'], row['offers'], row['bottom_banner'], version);
    });
  }

  /** Public slider list for `GET /banners` (JSON array of slides). */
  async getBannersArray(): Promise<HomeCmsSlide[]> {
    const cms = await this.getPublicCms();
    return cms.primarySlider;
  }
}
