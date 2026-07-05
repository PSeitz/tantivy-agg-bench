//! Empty crate root.
//!
//! This project exists only to host `benches/agg_bench.rs`, which benchmarks
//! tantivy's aggregations against whatever tantivy commit is pinned in
//! `Cargo.toml`. Cargo needs a lib (or bin) target for the bench to link
//! against, so this file is otherwise empty.

#[cfg(test)]
mod tests {
    use serde_json::json;
    use tantivy::aggregation::agg_req::Aggregations;

    // Mirrors the capability probes in `benches/agg_bench.rs`. If these ever
    // stop deserializing against the *pinned* tantivy, the benchmark would
    // silently skip composite/filter even on a build that supports them — so
    // keep these probes in sync with the ones used to gate registration.
    fn agg_supported(probe: serde_json::Value) -> bool {
        serde_json::from_value::<Aggregations>(probe).is_ok()
    }

    #[test]
    fn probes_deserialize_when_supported() {
        // These pass only if the pinned tantivy has the `composite`/`filter`
        // aggregations. Adjust expectations if you pin a version without them.
        assert!(agg_supported(
            json!({ "probe": { "composite": { "sources": [], "size": 1 } } })
        ));
        assert!(agg_supported(
            json!({ "probe": { "filter": "*", "aggs": {} } })
        ));
    }

    #[test]
    fn unknown_aggregation_is_not_supported() {
        // Sanity check that the gate returns false (rather than panicking or
        // accepting) for an aggregation the build doesn't know.
        assert!(!agg_supported(
            json!({ "probe": { "definitely_not_an_agg": {} } })
        ));
    }
}
