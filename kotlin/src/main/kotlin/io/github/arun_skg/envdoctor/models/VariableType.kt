package io.github.arun_skg.envdoctor.models

/**
 * The coarse type of an environment-variable value, inferred from its textual
 * form. Mirrors the reference `variable-type` model.
 */
enum class VariableType {
    UNKNOWN,
    INTEGER,
    FLOAT,
    BOOLEAN,
    URL,
    JSON,
    STRING,
}
