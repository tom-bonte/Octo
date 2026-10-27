import Foundation
import Testing

// Runs every @Test in this folder and exits with a failure code if any fail.
exit(await Testing.__swiftPMEntryPoint())
