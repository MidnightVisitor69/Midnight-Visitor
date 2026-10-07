extends "res://tests/test_case.gd"


func test_shop_hidden_at_launch() -> void:
	# Launch plan: shop stays behind the flag until the dev enables it.
	var cfg = load("res://scripts/config.gd")
	assert_eq(cfg.SHOP_ENABLED, false, "SHOP_ENABLED")


func test_client_key_is_publishable() -> void:
	# A secret/service key in the client would bypass RLS for every player.
	var cfg = load("res://scripts/config.gd")
	assert_true(String(cfg.SUPABASE_KEY).begins_with("sb_publishable_"), "client key must be publishable")
