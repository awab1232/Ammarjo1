-- Read-only mojibake scan: reports any row whose UTF-8 text column contains
-- a "double-encoding" artifact signature (e.g. "Ø§Ù„Ù…", "Ã˜", "Ã™"). Those
-- byte sequences result from writing Latin-1 bytes through a cp1256/windows
-- reader into a UTF-8 column without any real Arabic ever being present.

SET client_encoding TO 'UTF8';
DO $$
DECLARE
  r   record;
  cnt int;
  tot int := 0;
BEGIN
  FOR r IN
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND data_type IN ('text', 'character varying')
  LOOP
    EXECUTE format(
      'SELECT COUNT(*) FROM public.%I WHERE %I ~ $q$[ØÙ][ -]|Ã[˜™]$q$',
      r.table_name, r.column_name
    ) INTO cnt;
    IF cnt > 0 THEN
      RAISE NOTICE 'MOJIBAKE % row(s) in %.%', cnt, r.table_name, r.column_name;
      tot := tot + cnt;
    END IF;
  END LOOP;
  RAISE NOTICE 'TOTAL_MOJIBAKE_ROWS=%', tot;
END $$;
