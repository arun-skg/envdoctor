//! Portable snapshot token: `base64url(gzip(json))` with an `envd1:` prefix.
//! Compact enough to paste into an issue or chat, self-contained, and
//! schema-versioned so a decoder can refuse a token from a newer envdoctor
//! instead of mis-diffing it. Mirrors the TypeScript `runtime/token.ts`.

use crate::models::runtime_snapshot::SNAPSHOT_SCHEMA;
use crate::models::RuntimeSnapshot;
use base64::Engine;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use std::io::{Read, Write};

const PREFIX: &str = "envd1:";

/// Encode a snapshot into a single-line, paste-safe token.
pub fn encode_token(snapshot: &RuntimeSnapshot) -> anyhow::Result<String> {
    let json = serde_json::to_vec(snapshot)?;
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(&json)?;
    let gzipped = encoder.finish()?;
    let b64 = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(gzipped);
    Ok(format!("{PREFIX}{b64}"))
}

/// Decode a token back into a snapshot. Errors clearly on malformed or too-new
/// input.
pub fn decode_token(token: &str) -> anyhow::Result<RuntimeSnapshot> {
    let trimmed = token.trim();
    let body = trimmed
        .strip_prefix(PREFIX)
        .ok_or_else(|| anyhow::anyhow!("Not an envdoctor snapshot token (missing envd1: prefix)."))?;

    let gzipped = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(body)
        .map_err(|_| anyhow::anyhow!("Corrupt snapshot token: could not decode."))?;
    let mut decoder = GzDecoder::new(&gzipped[..]);
    let mut json = String::new();
    decoder
        .read_to_string(&mut json)
        .map_err(|_| anyhow::anyhow!("Corrupt snapshot token: could not decode."))?;
    let snapshot: RuntimeSnapshot = serde_json::from_str(&json)
        .map_err(|_| anyhow::anyhow!("Corrupt snapshot token: could not decode."))?;
    assert_readable(&snapshot)?;
    Ok(snapshot)
}

/// Parse raw JSON (from a `--output` file) into a validated snapshot.
pub fn parse_snapshot_json(text: &str) -> anyhow::Result<RuntimeSnapshot> {
    let snapshot: RuntimeSnapshot =
        serde_json::from_str(text).map_err(|_| anyhow::anyhow!("Invalid snapshot JSON."))?;
    assert_readable(&snapshot)?;
    Ok(snapshot)
}

/// Reject snapshots from a newer schema than this build understands.
fn assert_readable(snapshot: &RuntimeSnapshot) -> anyhow::Result<()> {
    if snapshot.schema.as_str() > SNAPSHOT_SCHEMA {
        anyhow::bail!(
            "Snapshot schema {} is newer than this envdoctor ({}). Upgrade to compare it.",
            snapshot.schema,
            SNAPSHOT_SCHEMA
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::runtime_snapshot::{OsInfo, ToolInfo};
    use std::collections::HashMap;

    fn sample_snapshot() -> RuntimeSnapshot {
        RuntimeSnapshot {
            schema: SNAPSHOT_SCHEMA.to_string(),
            captured_at: "2026-01-01T00:00:00Z".to_string(),
            os: OsInfo {
                platform: "linux".to_string(),
                arch: "x64".to_string(),
                release: "6.1.0".to_string(),
            },
            tools: vec![ToolInfo {
                tool: "node".to_string(),
                version: "20.0.0".to_string(),
                resolved_from: "PATH".to_string(),
            }],
            path: vec!["/usr/bin".to_string(), "/bin".to_string()],
            globals: HashMap::new(),
            env_flag_names: vec!["NODE_ENV".to_string()],
        }
    }

    #[test]
    fn encode_then_decode_round_trips() {
        let snapshot = sample_snapshot();
        let token = encode_token(&snapshot).unwrap();
        assert!(token.starts_with(PREFIX));
        let decoded = decode_token(&token).unwrap();
        assert_eq!(decoded, snapshot);
    }

    #[test]
    fn decode_rejects_missing_prefix() {
        let err = decode_token("not-a-token").unwrap_err();
        assert!(err.to_string().contains("envd1:"));
    }

    #[test]
    fn decode_rejects_corrupt_token() {
        // Valid prefix but the body is not valid base64url/gzip/json.
        assert!(decode_token("envd1:!!!not-base64!!!").is_err());
        assert!(decode_token("envd1:AAAA").is_err());
    }

    #[test]
    fn parse_snapshot_json_accepts_valid_and_rejects_invalid() {
        let snapshot = sample_snapshot();
        let json = serde_json::to_string(&snapshot).unwrap();
        let parsed = parse_snapshot_json(&json).unwrap();
        assert_eq!(parsed, snapshot);

        assert!(parse_snapshot_json("{ not valid json").is_err());
    }
}
