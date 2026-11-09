String? required_validator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}

String? port_validator(String? value) {
  final requiredError = required_validator(value);
  if (requiredError != null) {
    return requiredError;
  }
  final port = int.tryParse(value!.trim());
  if (port == null || port < 1 || port > 65535) {
    return 'Use a port from 1 to 65535';
  }
  return null;
}