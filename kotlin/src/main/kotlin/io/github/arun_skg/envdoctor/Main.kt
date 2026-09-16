package io.github.arun_skg.envdoctor

import kotlin.system.exitProcess

/** Native Kotlin envdoctor CLI entry point. */
fun main(args: Array<String>) {
    exitProcess(Cli.run(args))
}
