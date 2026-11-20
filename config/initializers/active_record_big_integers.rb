# On-chain values are numeric(78,0): salts and amounts are 256-bit by design. Rails 8.1 refuses integers
# over 64 bits when it quotes them instead of binding, which happens whenever prepared statements are
# off (query log tags in development, PgBouncer in production). Its reason, a slow scan when comparing
# with a bigint, does not apply to these columns.
ActiveRecord.raise_int_wider_than_64bit = false
