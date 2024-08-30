SELECT slot_name, slot_type, database, active FROM pg_replication_slots WHERE slot_type = 'logical';
