package struct LibraryRuntime {
    package let queries: LibraryQueries
    package let commands: LibraryCommands

    package init(
        queries: LibraryQueries,
        commands: LibraryCommands
    ) {
        self.queries = queries
        self.commands = commands
    }
}
