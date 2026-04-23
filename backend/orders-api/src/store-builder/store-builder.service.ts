import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import { DomainEventNames } from '../events/domain-event-names';
import { TenantContextService } from '../identity/tenant-context.service';
import { getFirebaseApp } from '../auth/firebase-admin';
import { AiStoreBuilderService } from './ai-store-builder.service';
import { isHybridStoreBuilderEnabled } from './store-builder.config';
import type {
  BootstrapStoreBuilderDto,
  CreateStoreCategoryDto,
  ReorderStoreCategoriesDto,
  SetStoreBuilderModeDto,
  StoreBuilderStoreType,
  StoreSuggestionRequestDto,
  UpdateStoreCategoryDto,
} from './store-builder.types';

@Injectable()
export class StoreBuilderService {
  private readonly logger = new Logger(StoreBuilderService.name);
  private readonly pool: Pool | null;

  constructor(
    private readonly events: DomainEventEmitterService,
    private readonly aiStoreBuilder: AiStoreBuilderService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.STORE_BUILDER_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireEnabled(): void {
    if (!isHybridStoreBuilderEnabled()) {
      throw new NotFoundException('Hybrid store builder is disabled');
    }
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('store builder database not configured');
    return this.pool;
  }

  private actorUid(): string {
    const uid = this.tenant?.getSnapshot().uid?.trim();
    if (!uid) throw new ForbiddenException('Authenticated actor is required');
    return uid;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private async assertStoreAccess(storeId: string, ownerId?: string): Promise<void> {
    const actor = this.actorUid();
    this.assertStoreAccessWithActor(storeId, ownerId, actor);
  }

  private assertStoreAccessWithActor(storeId: string, ownerId: string | undefined, actor: string): void {
    if (ownerId && ownerId.trim() && ownerId.trim() !== actor) {
      throw new ForbiddenException('Store owner mismatch');
    }
  }

  private async assertExistingStoreOwnership(client: PoolClient, storeId: string): Promise<void> {
    const actor = this.actorUid();
    await this.assertExistingStoreOwnershipForActor(client, storeId, actor);
  }

  private async assertExistingStoreOwnershipForActor(
    client: PoolClient,
    storeId: string,
    actor: string,
  ): Promise<void> {
    const q = await client.query(`SELECT owner_id FROM stores_builder WHERE store_id = $1 LIMIT 1`, [storeId]);
    if (q.rows.length === 0) {
      throw new NotFoundException('Store builder profile not found');
    }
    const ownerId = String(q.rows[0].owner_id ?? '').trim();
    if (!ownerId || ownerId !== actor) {
      throw new ForbiddenException('Store owner mismatch');
    }
  }

  private async resolveStoreTypeFromContextOrThrow(
    dtoStoreType?: string,
  ): Promise<'construction_store' | 'home_store' | 'wholesale_store'> {
    const snap = this.tenant?.getSnapshot();
    const uid = snap?.uid?.trim() || '';
    const fromSnapshot = snap?.storeType?.trim();
    const fromClaimsStoreType =
      typeof snap?.customClaims?.['storeType'] === 'string'
        ? String(snap?.customClaims?.['storeType']).trim()
        : null;
    const fromClaimsStoreTypeSnake =
      typeof snap?.customClaims?.['store_type'] === 'string'
        ? String(snap?.customClaims?.['store_type']).trim()
        : null;
    let profileStoreType: string | null = null;
    if (!fromSnapshot && !fromClaimsStoreType && !fromClaimsStoreTypeSnake && uid) {
      try {
        const fs = getFirebaseApp().firestore();
        const profileDoc = await fs.collection('users').doc(uid).get();
        const raw = profileDoc.exists ? profileDoc.get('storeType') ?? profileDoc.get('store_type') : null;
        profileStoreType = raw != null ? String(raw).trim() : null;
      } catch (e) {
        this.logger.warn(
          JSON.stringify({
            kind: 'store_builder_store_type_profile_lookup_failed',
            uid,
            reason: e instanceof Error ? e.message : String(e),
          }),
        );
      }
    }
    const resolved =
      fromSnapshot ||
      fromClaimsStoreType ||
      fromClaimsStoreTypeSnake ||
      profileStoreType ||
      dtoStoreType?.trim() ||
      '';
    if (resolved !== 'construction_store' && resolved !== 'home_store' && resolved !== 'wholesale_store') {
      throw new BadRequestException(
        'storeType is required in authenticated tenant context and must be one of: construction_store, home_store, wholesale_store',
      );
    }
    return resolved;
  }

  async bootstrap(dto: BootstrapStoreBuilderDto) {
    return this.bootstrapWithActor(dto, this.actorUid());
  }

  /**
   * Bootstrap using a fixed actor UID (internal dev seed / tooling) without Firebase tenant context.
   */
  async bootstrapForDevSeed(dto: BootstrapStoreBuilderDto, actorUid: string) {
    return this.bootstrapWithActor(dto, actorUid);
  }

  private async bootstrapWithActor(dto: BootstrapStoreBuilderDto, actorUid: string) {
    this.requireEnabled();
    this.assertStoreAccessWithActor(dto.storeId, dto.ownerId, actorUid);
    const ownerId = dto.ownerId?.trim() || actorUid;
    const storeId = dto.storeId.trim();
    const storeType = await this.resolveStoreTypeFromContextOrThrow(dto.storeType);
    this.logger.log(
      JSON.stringify({
        kind: 'store_builder_bootstrap_store_type_resolved',
        storeId,
        ownerId,
        storeType,
      }),
    );
    return this.withClient(async (client) => {
      await client.query('BEGIN');
      try {
        const existing = await client.query(`SELECT * FROM stores_builder WHERE store_id = $1 LIMIT 1`, [
          storeId,
        ]);
        if (existing.rows.length > 0) {
          const existingOwner = String(existing.rows[0].owner_id ?? '').trim();
          if (existingOwner && existingOwner !== ownerId) {
            throw new ForbiddenException('Store owner mismatch');
          }
          await client.query('COMMIT');
          return this.getStoreBuilderWithActor(storeId, actorUid);
        }
        const builderId = randomUUID();
        await client.query(
          `INSERT INTO stores_builder (id, store_id, owner_id, store_type, mode, ai_generated, created_at, updated_at)
           VALUES ($1::uuid, $2, $3, $4, 'AI', true, NOW(), NOW())`,
          [builderId, storeId, ownerId, storeType],
        );

        const structure = this.aiStoreBuilder.buildInitialStructure(storeType);
        for (const cat of structure.categories) {
          const categoryId = randomUUID();
          await client.query(
            `INSERT INTO store_categories (id, store_id, name, image_url, parent_id, sort_order, is_ai_generated, created_at, updated_at)
             VALUES ($1::uuid, $2, $3, $4, NULL, $5, true, NOW(), NOW())`,
            [categoryId, storeId, cat.name, cat.imageUrl, cat.sortOrder],
          );
          for (const sub of cat.children) {
            await client.query(
              `INSERT INTO store_categories (id, store_id, name, image_url, parent_id, sort_order, is_ai_generated, created_at, updated_at)
               VALUES ($1::uuid, $2, $3, $4, $5::uuid, $6, true, NOW(), NOW())`,
              [randomUUID(), storeId, sub.name, sub.imageUrl, categoryId, sub.sortOrder],
            );
          }
        }

        for (const section of structure.layoutSections) {
          await client.query(
            `INSERT INTO store_layout_sections (id, store_id, section_type, sort_order, config_json, is_ai_generated, created_at, updated_at)
             VALUES ($1::uuid, $2, $3, $4, $5::jsonb, true, NOW(), NOW())`,
            [randomUUID(), storeId, section.sectionType, section.sortOrder, JSON.stringify(section.configJson)],
          );
        }
        await this.events.enqueueInTransaction(client, DomainEventNames.STORE_BUILDER_BOOTSTRAPPED, storeId, {
          storeId,
          ownerId,
          storeType,
          mode: 'AI',
        });
        await client.query('COMMIT');
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
      return this.getStoreBuilderWithActor(storeId, actorUid);
    });
  }

  async getStoreBuilder(storeId: string) {
    this.requireEnabled();
    const sid = storeId.trim();
    await this.assertStoreAccess(sid);
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnership(client, sid);
      return this.loadStoreBuilderPayload(client, sid);
    });
  }

  async getStoreBuilderWithActor(storeId: string, actorUid: string) {
    this.requireEnabled();
    const sid = storeId.trim();
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnershipForActor(client, sid, actorUid);
      return this.loadStoreBuilderPayload(client, sid);
    });
  }

  private async loadStoreBuilderPayload(client: PoolClient, storeId: string) {
    const storeQ = await client.query(`SELECT * FROM stores_builder WHERE store_id = $1 LIMIT 1`, [storeId]);
    if (storeQ.rows.length === 0) {
      throw new NotFoundException('Store builder profile not found');
    }
    const categoriesQ = await client.query(
      `SELECT * FROM store_categories WHERE store_id = $1 ORDER BY parent_id NULLS FIRST, sort_order ASC, created_at ASC`,
      [storeId],
    );
    const layoutQ = await client.query(
      `SELECT * FROM store_layout_sections WHERE store_id = $1 ORDER BY sort_order ASC, created_at ASC`,
      [storeId],
    );
    return {
      store: {
        id: String(storeQ.rows[0].id),
        storeId: String(storeQ.rows[0].store_id),
        ownerId: String(storeQ.rows[0].owner_id),
        storeType: String(storeQ.rows[0].store_type),
        mode: String(storeQ.rows[0].mode),
        aiGenerated: Boolean(storeQ.rows[0].ai_generated),
      },
      categories: categoriesQ.rows.map((r) => ({
        id: String(r.id),
        storeId: String(r.store_id),
        name: String(r.name),
        imageUrl: String(r.image_url ?? ''),
        parentId: r.parent_id != null ? String(r.parent_id) : null,
        sortOrder: Number(r.sort_order ?? 0),
        isAiGenerated: Boolean(r.is_ai_generated),
      })),
      layoutSections: layoutQ.rows.map((r) => ({
        id: String(r.id),
        sectionType: String(r.section_type),
        sortOrder: Number(r.sort_order ?? 0),
        configJson: (r.config_json as Record<string, unknown>) ?? {},
        isAiGenerated: Boolean(r.is_ai_generated),
      })),
    };
  }

  async setMode(storeId: string, dto: SetStoreBuilderModeDto) {
    this.requireEnabled();
    const sid = storeId.trim();
    await this.assertStoreAccess(sid);
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnership(client, sid);
      const q = await client.query(
        `UPDATE stores_builder
         SET mode = $2, updated_at = NOW()
         WHERE store_id = $1
         RETURNING *`,
        [sid, dto.mode],
      );
      if (q.rows.length === 0) throw new NotFoundException('Store builder profile not found');
      const row = q.rows[0];
      this.events.dispatch(DomainEventNames.STORE_BUILDER_MODE_CHANGED, sid, {
        storeId: sid,
        mode: dto.mode,
      });
      return {
        storeId: sid,
        mode: String(row.mode),
        aiGenerated: Boolean(row.ai_generated),
      };
    });
  }

  async addCategory(storeId: string, dto: CreateStoreCategoryDto) {
    this.requireEnabled();
    const sid = storeId.trim();
    await this.assertStoreAccess(sid);
    const id = randomUUID();
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnership(client, sid);
      const q = await client.query(
        `INSERT INTO store_categories (id, store_id, name, image_url, parent_id, sort_order, is_ai_generated, created_at, updated_at)
         VALUES (
           $1::uuid, $2, $3, $4, $5::uuid,
           COALESCE((SELECT MAX(sort_order) + 1 FROM store_categories WHERE store_id = $2), 1),
           false, NOW(), NOW()
         )
         RETURNING *`,
        [id, sid, dto.name.trim(), dto.imageUrl?.trim() ?? '', dto.parentId ?? null],
      );
      this.events.dispatch(DomainEventNames.STORE_BUILDER_CATEGORY_UPDATED, sid, {
        storeId: sid,
        categoryId: id,
        action: 'create',
      });
      return q.rows[0];
    });
  }

  async updateCategory(storeId: string, categoryId: string, dto: UpdateStoreCategoryDto) {
    this.requireEnabled();
    const sid = storeId.trim();
    await this.assertStoreAccess(sid);
    const patches: string[] = [];
    const params: Array<string | number> = [sid, categoryId.trim()];
    let idx = 3;
    if (dto.name != null) {
      patches.push(`name = $${idx++}`);
      params.push(dto.name.trim());
    }
    if (dto.imageUrl != null) {
      patches.push(`image_url = $${idx++}`);
      params.push(dto.imageUrl.trim());
    }
    patches.push(`is_ai_generated = false`);
    patches.push(`updated_at = NOW()`);
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnership(client, sid);
      const q = await client.query(
        `UPDATE store_categories SET ${patches.join(', ')}
         WHERE store_id = $1 AND id = $2::uuid
         RETURNING *`,
        params,
      );
      if (q.rows.length === 0) throw new NotFoundException('Category not found');
      this.events.dispatch(DomainEventNames.STORE_BUILDER_CATEGORY_UPDATED, sid, {
        storeId: sid,
        categoryId: categoryId.trim(),
        action: 'update',
      });
      return q.rows[0];
    });
  }

  async deleteCategory(storeId: string, categoryId: string) {
    this.requireEnabled();
    const sid = storeId.trim();
    await this.assertStoreAccess(sid);
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnership(client, sid);
      const q = await client.query(`DELETE FROM store_categories WHERE store_id = $1 AND id = $2::uuid`, [
        sid,
        categoryId.trim(),
      ]);
      if ((q.rowCount ?? 0) === 0) throw new NotFoundException('Category not found');
      this.events.dispatch(DomainEventNames.STORE_BUILDER_CATEGORY_UPDATED, sid, {
        storeId: sid,
        categoryId: categoryId.trim(),
        action: 'delete',
      });
      return { ok: true };
    });
  }

  async reorderCategories(storeId: string, dto: ReorderStoreCategoriesDto) {
    this.requireEnabled();
    const sid = storeId.trim();
    await this.assertStoreAccess(sid);
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnership(client, sid);
      await client.query('BEGIN');
      try {
        for (const item of dto.items) {
          await client.query(
            `UPDATE store_categories
             SET sort_order = $3, is_ai_generated = false, updated_at = NOW()
             WHERE store_id = $1 AND id = $2::uuid`,
            [sid, item.id, item.sortOrder],
          );
        }
        await this.events.enqueueInTransaction(client, DomainEventNames.STORE_BUILDER_CATEGORY_UPDATED, sid, {
          storeId: sid,
          action: 'reorder',
          count: dto.items.length,
        });
        await client.query('COMMIT');
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
      return { ok: true };
    });
  }

  async suggest(dto: StoreSuggestionRequestDto) {
    this.requireEnabled();
    const sid = dto.storeId.trim();
    await this.assertStoreAccess(sid);
    return this.withClient(async (client) => {
      await this.assertExistingStoreOwnership(client, sid);
      const storeQ = await client.query(`SELECT store_type, mode FROM stores_builder WHERE store_id = $1 LIMIT 1`, [sid]);
      if (storeQ.rows.length === 0) throw new NotFoundException('Store builder profile not found');
      const storeType = String(storeQ.rows[0].store_type) as StoreBuilderStoreType;
      const mode = String(storeQ.rows[0].mode);
      const suggestions = this.aiStoreBuilder.buildSuggestions(storeType);
      await client.query(
        `INSERT INTO store_ai_suggestions (id, store_id, type, suggestion_json, created_at)
         VALUES ($1::uuid, $2, 'layout', $3::jsonb, NOW())`,
        [randomUUID(), sid, JSON.stringify({ mode, ...suggestions })],
      );
      this.events.dispatch(DomainEventNames.STORE_BUILDER_SUGGESTION_CREATED, sid, {
        storeId: sid,
        mode,
      });
      return { storeId: sid, mode, ...suggestions };
    });
  }
}

