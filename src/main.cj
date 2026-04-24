package metis


@When[os == "Windows"]
import magic.utils.winGetArgs

@When[os == "Windows"]
main(): Int64 {
    // On Windows, we cannot use main(args: Array<String>) because
    // the standard library has a bug when parsing Unicode command line arguments.
    let args = winGetArgs()
    return cliMain(args)
}

@When[os != "Windows"]
main(args: Array<String>): Int64 {
    return cliMain(args)
}

func cliMain(args: Array<String>): Int64 {
    runCliProgram(args)
}
