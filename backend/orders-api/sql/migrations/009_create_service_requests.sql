CREATE TABLE IF NOT EXISTS service_requests (
  id uuid PRIMARY KEY,
  tenant_id text NULL,
  customer_id text NOT NULL,
  technician_id text NULL,
  conversation_id text NOT NULL UNIQUE,
  status text NOT NULL CHECK (status IN ('pending', 'assigned', 'in_progress', 'completed', 'cancelled')),
  description text NOT NULL DEFAULT '',
  title text NOT NULL DEFAULT '',
  category_id text NOT NULL DEFAULT '',
  image_url text NULL,
  notes text NOT NULL DEFAULT '',
  chat_id text NULL,
  technician_email text NULL,
  earnings_amount numeric(18,4) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS title text NOT NULL DEFAULT '';
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS tenant_id text NULL;
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS category_id text NOT NULL DEFAULT '';
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS image_url text NULL;
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS notes text NOT NULL DEFAULT '';
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS chat_id text NULL;
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS technician_email text NULL;
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS earnings_amount numeric(18,4) NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_service_requests_customer_id ON service_requests (customer_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_tenant_id ON service_requests (tenant_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_technician_id ON service_requests (technician_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_status ON service_requests (status);
CREATE INDEX IF NOT EXISTS idx_service_requests_created_at ON service_requests (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_requests_customer_created_at ON service_requests (customer_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_service_requests_technician_created_at ON service_requests (technician_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS service_request_status_history (
  id bigserial PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('pending', 'assigned', 'in_progress', 'completed', 'cancelled')),
  changed_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_service_request_status_history_request_id
  ON service_request_status_history (request_id, created_at DESC);

