class_name Ads
extends RefCounted
## Rewarded ad flow (T-015). The client ONLY requests an ad and sends the
## reward_id it wants; the grant happens server-side via the SSV callback.
##
## Feature flag: ads_enabled in app_config (default false). When off, no ad UI
## appears and the edge function rejects grants.
##
## No network calls in tests: the ad flow is pure logic + a stubbed "show_ad"
## that tests can override. The real AdMob SDK integration is a thin wrapper
## around this class (separate file, not in repo until the dev adds the account).

## Reward IDs must match the server's rewards table.
const REWARD_GEMS_SMALL := "gems_small"
const REWARD_STREAK_REPAIR := "streak_repair"

## Max ads per day (server-enforced; client shows the same cap for UX).
const MAX_ADS_PER_DAY := 4

## Result of an ad request.
## - ok: the ad was shown and the SSV callback *will* grant (or already granted).
## - error: user-facing message.
## - reward_id: which reward was requested.
## - ssv_event_id: the event id the server will use for idempotency (timestamp).
class AdResult:
	var ok: bool = false
	var error: String = ""
	var reward_id: String = ""
	var ssv_event_id: String = ""

## Callback signature for the ad SDK wrapper.
## The wrapper calls this when the ad closes (rewarded or not).
## In tests, we inject a fake that immediately calls back with success/failure.
## (Godot 4 doesn't support type aliases in class bodies; Callable is used directly.)

static var _show_ad_impl: Callable = _show_ad_stub
static var _first_session_done: bool = false

## Inject a custom ad shower (tests, or the real AdMob wrapper).
static func set_show_ad_impl(impl: Callable) -> void:
	_show_ad_impl = impl

## Reset to the stub (tests call this in tear-down).
static func reset_show_ad_impl() -> void:
	_show_ad_impl = _show_ad_stub

## Mark that the player has finished their first session (no ad prompts before).
static func mark_first_session_done() -> void:
	_first_session_done = true

## Check if ads are enabled (feature flag from home payload).
static func is_enabled(home: Dictionary) -> bool:
	return bool(home.get("ads_enabled", false))

## Check if we can prompt for an ad now (feature flag + first session done).
static func can_prompt(home: Dictionary) -> bool:
	return is_enabled(home) and _first_session_done

## Request a rewarded ad for the given reward.
## Returns an AdResult immediately; the actual grant is async via SSV.
## The caller should show a loading state and wait for the home refresh.
static func request_reward(reward_id: String, home: Dictionary, supabase: Node) -> AdResult:
	var result: AdResult = AdResult.new()
	result.reward_id = reward_id

	if not is_enabled(home):
		result.error = "Rewarded ads are disabled."
		return result

	if not _first_session_done:
		result.error = "No ads in first session."
		return result

	# Client-side pre-check for daily cap (server is the authority).
	var ads_today := int(home.get("ads_today", 0))
	if ads_today >= MAX_ADS_PER_DAY:
		result.error = "Daily ad limit reached."
		return result

	# Generate an idempotency key for this ad request (client-side only;
	# the server uses the SSV event id for true idempotency).
	var crypto := Crypto.new()
	var client_key := crypto.generate_random_bytes(16).hex_encode()

	# Build the custom_data payload for the ad request.
	# The SSV callback receives this and extracts reward_id.
	var custom_data := JSON.stringify({"reward_id": reward_id, "client_key": client_key})

	# The real AdMob wrapper would call _show_ad_impl with the ad unit ID
	# and custom_data. Here we just invoke the injected impl.
	# The impl MUST call back with (success: bool, ssv_event_id: String).
	# In production, the SSV callback hits the edge function independently;
	# the client doesn't wait for it. But for tests we simulate the callback.
	var ssv_event_id := "ssv_" + str(Time.get_unix_time_from_system() * 1000 + Time.get_ticks_msec())
	result.ssv_event_id = ssv_event_id

	# Fire and forget: the ad SDK shows the ad, user watches/closes,
	# Google calls our SSV endpoint, which calls ad_reward().
	# The client just refreshes home when the ad closes.
	_show_ad_impl.call(reward_id, custom_data, ssv_event_id, Callable(_on_ad_closed).bind(result, supabase))

	result.ok = true
	return result

## Internal: called when the ad SDK reports the ad closed.
## In production this just triggers a home refresh; the grant already happened
## (or will happen) via the SSV callback. In tests the stub calls this directly.
static func _on_ad_closed(success: bool, ssv_event_id: String, result: AdResult, supabase: Node) -> void:
	if not success:
		result.ok = false
		result.error = "Ad not completed."
		return
	# The SSV callback is async; we don't wait for it here.
	# The caller (Home tab) should refresh home after a short delay or on a signal.
	# For tests, we simulate the grant by calling the RPC directly (see test_ads.gd).

## Stub implementation for tests / when no AdMob SDK is present.
## Immediately calls back with success=true and a fake ssv_event_id.
static func _show_ad_stub(reward_id: String, custom_data: String, ssv_event_id: String, callback: Callable) -> void:
	# In tests, the test overrides this or calls the callback directly.
	# The stub does nothing; the test drives the flow.
	pass

## Parse the home payload for ad-related fields.
static func parse_ad_fields(home: Dictionary) -> Dictionary:
	return {
		"ads_enabled": bool(home.get("ads_enabled", false)),
		"ads_today": int(home.get("ads_today", 0)),
		"max_ads_per_day": MAX_ADS_PER_DAY,
	}