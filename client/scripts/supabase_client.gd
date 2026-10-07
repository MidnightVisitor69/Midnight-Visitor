extends Node
## Thin Supabase wrapper: email auth + RPC. The client only requests actions;
## all game outcomes are decided by Postgres functions.

signal signed_in
signal auth_failed(message: String)

const SESSION_PATH := "user://session.json"

var access_token := ""
var refresh_token := ""
var user_id := ""


func _ready() -> void:
	_load_session()


func is_signed_in() -> bool:
	return access_token != ""


func sign_up(email: String, password: String) -> void:
	await _auth("/auth/v1/signup", {"email": email, "password": password})


func sign_in(email: String, password: String) -> void:
	await _auth("/auth/v1/token?grant_type=password", {"email": email, "password": password})


func refresh() -> bool:
	if refresh_token == "":
		return false
	await _auth("/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token})
	return is_signed_in()


## Calls a Postgres function. Returns {"ok": bool, "data": Variant, "error": String}.
## Callers supply an idempotency key for every write action.
## Named call_rpc because Node already defines rpc() for multiplayer.
func call_rpc(fn: String, args: Dictionary = {}) -> Dictionary:
	var res := await _request("/rest/v1/rpc/" + fn, args)
	return _wrap(res)


## Reads a table or view (RLS limits rows to the signed-in user).
func select(table: String, query: String = "select=*") -> Dictionary:
	var res := await _request("/rest/v1/%s?%s" % [table, query], null, HTTPClient.METHOD_GET)
	return _wrap(res)


func new_idempotency_key() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


func sign_out() -> void:
	access_token = ""
	refresh_token = ""
	user_id = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))


func _auth(path: String, body: Dictionary) -> void:
	var res := await _request(path, body, HTTPClient.METHOD_POST, false)
	var data = res.get("body")
	if res.code >= 200 and res.code < 300 and data is Dictionary and data.has("access_token"):
		access_token = data["access_token"]
		refresh_token = data.get("refresh_token", "")
		user_id = data.get("user", {}).get("id", "")
		_save_session()
		signed_in.emit()
	else:
		var msg := "Sign-in failed"
		if data is Dictionary:
			msg = str(data.get("msg", data.get("error_description", msg)))
		auth_failed.emit(msg)


func _request(path: String, body: Variant, method := HTTPClient.METHOD_POST, use_token := true) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray([
		"apikey: " + Config.SUPABASE_KEY,
		"Content-Type: application/json",
		"Authorization: Bearer " + (access_token if use_token and access_token != "" else Config.SUPABASE_KEY),
	])
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(Config.SUPABASE_URL + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"code": 0, "body": null}
	var r: Array = await http.request_completed
	http.queue_free()
	var text: String = r[3].get_string_from_utf8()
	return {"code": r[1], "body": JSON.parse_string(text) if text != "" else null}


func _wrap(res: Dictionary) -> Dictionary:
	if res.code >= 200 and res.code < 300:
		return {"ok": true, "data": res.body, "error": ""}
	var msg := "Request failed (%d)" % res.code
	if res.body is Dictionary:
		msg = str(res.body.get("message", msg))
	return {"ok": false, "data": null, "error": msg}


func _save_session() -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"access": access_token, "refresh": refresh_token, "uid": user_id}))


func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if d is Dictionary:
		access_token = d.get("access", "")
		refresh_token = d.get("refresh", "")
		user_id = d.get("uid", "")
