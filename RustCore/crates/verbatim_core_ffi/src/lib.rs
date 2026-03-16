use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use verbatim_core_contract as contract;

#[derive(Default)]
struct Engine {
    trigger_engine: contract::TriggerEngine,
}

#[derive(Serialize)]
struct ResponseEnvelope<T: Serialize> {
    ok: bool,
    value: Option<T>,
    error: Option<String>,
}

#[no_mangle]
pub extern "C" fn verbatim_core_engine_new() -> *mut c_void {
    Box::into_raw(Box::new(Engine::default())) as *mut c_void
}

#[no_mangle]
pub extern "C" fn verbatim_core_engine_free(engine: *mut c_void) {
    if engine.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(engine as *mut Engine));
    }
}

#[no_mangle]
pub extern "C" fn verbatim_core_version() -> *const c_char {
    static VERSION: &str = "0.1.0\0";
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn verbatim_core_free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}

#[no_mangle]
pub extern "C" fn verbatim_core_prepare_trigger(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(engine, request_json, |engine, request: contract::PrepareTriggerRequest| {
        engine.trigger_engine.prepare_trigger(request.mode);
        Ok(contract::EmptyResponse::default())
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_capabilities(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |_engine, request: contract::CapabilityResolutionRequest| Ok(contract::resolve_capabilities(request)),
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_selection(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |_engine, request: contract::SelectionResolutionRequest| {
            Ok(contract::resolve_selection_response(request))
        },
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_provider_model_selection(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |_engine, request: contract::ProviderModelSelectionRequest| {
            Ok(contract::resolve_provider_model_selection(request))
        },
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_build_history_sections(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |_engine, request: contract::HistorySectionsRequest| Ok(contract::build_history_sections(request)),
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_reduce_provider_diagnostics(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |_engine, request: contract::ProviderDiagnosticsRequest| {
            Ok(contract::reduce_provider_diagnostics(request))
        },
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_summarize_trigger_state(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |engine, request: contract::SummarizeTriggerStateRequest| {
            Ok(engine.trigger_engine.summarize_trigger_state(request))
        },
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_handle_input_event(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |engine, request: contract::HandleInputEventRequest| {
            Ok(engine.trigger_engine.handle_input_event(request))
        },
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_style_context(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |_engine, request: contract::ResolveStyleContextRequest| {
            Ok(contract::resolve_style_context(&request.context, &request.settings))
        },
    )
}

#[no_mangle]
pub extern "C" fn verbatim_core_process_transcript(
    engine: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    respond(
        engine,
        request_json,
        |_engine, request: contract::ProcessTranscriptRequest| Ok(contract::process_transcript(request)),
    )
}

fn respond<Request, Response, F>(
    engine: *mut c_void,
    request_json: *const c_char,
    handler: F,
) -> *mut c_char
where
    Request: for<'de> Deserialize<'de>,
    Response: Serialize,
    F: FnOnce(&mut Engine, Request) -> Result<Response, String>,
{
    let envelope = (|| {
        if engine.is_null() {
            return ResponseEnvelope::<Response> {
                ok: false,
                value: None,
                error: Some("Engine was null.".to_string()),
            };
        }
        let request_str = unsafe { c_str_to_string(request_json) };
        let request = match serde_json::from_str::<Request>(&request_str) {
            Ok(request) => request,
            Err(error) => {
                return ResponseEnvelope::<Response> {
                    ok: false,
                    value: None,
                    error: Some(format!("Invalid request JSON: {error}")),
                }
            }
        };
        let engine = unsafe { &mut *(engine as *mut Engine) };
        match handler(engine, request) {
            Ok(value) => ResponseEnvelope {
                ok: true,
                value: Some(value),
                error: None,
            },
            Err(error) => ResponseEnvelope {
                ok: false,
                value: None,
                error: Some(error),
            },
        }
    })();

    json_to_ptr(&envelope)
}

unsafe fn c_str_to_string(value: *const c_char) -> String {
    if value.is_null() {
        return String::new();
    }
    CStr::from_ptr(value).to_string_lossy().into_owned()
}

fn json_to_ptr<T: Serialize>(value: &T) -> *mut c_char {
    let json = serde_json::to_string(value).unwrap_or_else(|error| {
        format!(
            "{{\"ok\":false,\"value\":null,\"error\":\"Serialization error: {}\"}}",
            escape_json(&error.to_string())
        )
    });
    CString::new(json).unwrap().into_raw()
}

fn escape_json(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_wraps_successful_json_response() {
        let engine = verbatim_core_engine_new();
        let request = CString::new(r#"{"mode":"hold"}"#).unwrap();

        let response_ptr = verbatim_core_prepare_trigger(engine, request.as_ptr());
        let response = unsafe { CStr::from_ptr(response_ptr) }
            .to_string_lossy()
            .into_owned();

        assert!(response.contains("\"ok\":true"));
        verbatim_core_free_string(response_ptr);
        verbatim_core_engine_free(engine);
    }

    #[test]
    fn ffi_rejects_invalid_json() {
        let engine = verbatim_core_engine_new();
        let request = CString::new("not-json").unwrap();

        let response_ptr = verbatim_core_prepare_trigger(engine, request.as_ptr());
        let response = unsafe { CStr::from_ptr(response_ptr) }
            .to_string_lossy()
            .into_owned();

        assert!(response.contains("Invalid request JSON"));
        verbatim_core_free_string(response_ptr);
        verbatim_core_engine_free(engine);
    }
}
