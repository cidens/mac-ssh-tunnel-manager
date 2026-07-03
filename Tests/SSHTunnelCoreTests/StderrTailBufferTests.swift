import Testing
@testable import SSHTunnelCore

@Test func stderrTailBufferKeepsOnlyRecentLines() {
    let buffer = StderrTailBuffer(maxLines: 3)

    buffer.append("one\ntwo\n")
    buffer.append("three\nfour\n")

    #expect(buffer.text == "two\nthree\nfour")
}

@Test func stderrTailBufferTrimsBlankOutput() {
    let buffer = StderrTailBuffer(maxLines: 3)

    buffer.append("\n warning \n\n")

    #expect(buffer.text == "warning")
}
