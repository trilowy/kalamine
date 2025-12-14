pub const CliError = error{
    MissingArg,
    UnknownCommand,
    WrongArgValue,
    DuplicatedArg,
};
