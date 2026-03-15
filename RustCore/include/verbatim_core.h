#ifndef VERBATIM_CORE_H
#define VERBATIM_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

void *verbatim_core_engine_new(void);
void verbatim_core_engine_free(void *engine);
const char *verbatim_core_version(void);
char *verbatim_core_prepare_trigger(void *engine, const char *request_json);
char *verbatim_core_resolve_capabilities(void *engine, const char *request_json);
char *verbatim_core_summarize_trigger_state(void *engine, const char *request_json);
char *verbatim_core_handle_input_event(void *engine, const char *request_json);
char *verbatim_core_resolve_style_context(void *engine, const char *request_json);
char *verbatim_core_process_transcript(void *engine, const char *request_json);
void verbatim_core_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
