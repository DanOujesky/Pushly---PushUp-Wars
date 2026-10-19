package app.pushly.engine.rep

import app.pushly.engine.rep.generated.PushupSpecV1

/**
 * RepEngine entry point. The state machine is implemented in roadmap task P3-06 (doc 05 §4–5).
 * Constants come only from the generated [PushupSpecV1] (shared/rep-engine-spec).
 */
object RepEngineInfo {
    const val SPEC_VERSION: Int = PushupSpecV1.SPEC_VERSION
}
