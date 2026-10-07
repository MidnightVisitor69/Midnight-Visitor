extends "res://tests/test_case.gd"
## T-000: every write action carries an idempotency key, and the server's
## idempotency_keys.key check constraint rejects keys outside 8-64 chars.
## These tests pin the client-side key shape and the HTTP response mapping.

const SupabaseClient := preload("res://scripts/supabase_client.gd")
const HEX_CHARS := "0123456789abcdef"


## Tree-less instance: _ready() is never called, so no session file is read and
## no request is made. Tests must stay offline.
func _make_client() -> SupabaseClient:
	return SupabaseClient.new()


## Node is not reference-counted, so a client left outside the tree would leak
## and make the runner print ObjectDB errors.
func _drop_client(client: SupabaseClient) -> void:
	client.free()


func test_idempotency_key_is_valid_shape() -> void:
	var client := _make_client()
	var key: String = client.new_idempotency_key()
	assert_true(key.length() >= 8, "key must be >= 8 chars, got %d" % key.length())
	assert_true(key.length() <= 64, "key must be <= 64 chars, got %d" % key.length())
	for i in key.length():
		# hex_encode() must stay lowercase; uppercase hex would still pass the
		# 8-64 check, but the documented key format is lowercase.
		assert_true(HEX_CHARS.contains(key[i]), "key char %d (%s) is not lowercase hex" % [i, key[i]])
	_drop_client(client)


func test_idempotency_keys_are_distinct() -> void:
	var client := _make_client()
	var seen := {}
	for i in 200:
		var key: String = client.new_idempotency_key()
		assert_true(key.length() >= 8 and key.length() <= 64, "key %d shape" % i)
		seen[key] = true
	assert_eq(seen.size(), 200, "200 calls must yield 200 distinct keys")
	_drop_client(client)


func test_wrap_maps_success() -> void:
	var client := _make_client()
	var out: Dictionary = client._wrap({"code": 200, "body": {"gems": 42}})
	assert_eq(out["ok"], true, "200 should be ok")
	assert_eq(out["error"], "", "200 should have empty error")
	var data = out["data"]
	assert_true(data is Dictionary and data.get("gems") == 42, "200 should pass body through as data")
	_drop_client(client)


func test_wrap_surfaces_400_message() -> void:
	var client := _make_client()
	var out: Dictionary = client._wrap({"code": 400, "body": {"message": "not enough gems"}})
	assert_eq(out["ok"], false, "400 should not be ok")
	assert_eq(out["error"], "not enough gems", "400 should surface the server message")
	assert_eq(out["data"], null, "400 should carry no data")
	_drop_client(client)


func test_wrap_reports_transport_failure() -> void:
	var client := _make_client()
	var out: Dictionary = client._wrap({"code": 0, "body": null})
	assert_eq(out["ok"], false, "transport failure should not be ok")
	assert_true(String(out["error"]) != "", "transport failure needs a non-empty error")
	_drop_client(client)
