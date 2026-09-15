package io.github.arun_skg.envdoctor.utils

import java.io.PrintStream

/**
 * Output sink matching the reference CLI's byte contract: `\n` line endings
 * on every platform (the reference runs on Node, which always emits `\n`),
 * with [err] going to stderr.
 */
object Out {
    val out: PrintStream = System.out
    val err: PrintStream = System.err

    fun println(s: String = "") {
        out.print(s)
        out.print('\n')
    }

    fun eprintln(s: String) {
        err.print(s)
        err.print('\n')
    }
}
