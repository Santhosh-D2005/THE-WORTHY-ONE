class_name BackendConfig
extends RefCounted
## Where the online services are. Only PUBLIC values live here: the project URL and the publishable key (designed to be shipped in an app;
## the database rules, not this key, protect the data). The service-role / secret key must NEVER appear in this project. A test checks it.

const URL := "https://cobpxlanflhzqyjnyoti.supabase.co"
const PUBLISHABLE_KEY := "sb_publishable_wMse-Rr4-lxXQPRF-tI3tA_HNUhAmgZ"
const TIMEOUT_SECONDS := 12.0
