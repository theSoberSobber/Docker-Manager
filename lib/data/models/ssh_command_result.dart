class SSHCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const SSHCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}