part of 'aws.dart';

/// A mixin that provides AWS Signature Version 4 signing capabilities for HTTP requests.
///
/// This mixin handles the signing of AWS API requests using the AWS Signature Version 4
/// algorithm, including creation of presigned URLs and sending authenticated requests.
mixin Signer {
  /// The AWS region where the service is located (e.g., 'us-east-1', 'eu-west-1').
  String get region;

  /// The AWS service name (e.g., AWSService.s3, AWSService.cognitoIdentityProvider).
  AWSService get service;

  /// Provides the AWS credentials (access key, secret key, and optional session token)
  /// used for signing requests.
  AWSCredentialsProvider get credentialsProvider;

  late final _signer = AWSSigV4Signer(credentialsProvider: credentialsProvider);

  /// The credential scope defining the region and service for signing requests.
  late final _scope = AWSCredentialScope(region: region, service: service);

  /// Returns the service-specific configuration for request signing.
  ///
  /// Returns [S3ServiceConfiguration] for S3 service, otherwise returns [BaseServiceConfiguration].
  ServiceConfiguration get config {
    return switch (service) {
      .s3 => S3ServiceConfiguration(signPayload: false),
      _ => const BaseServiceConfiguration(),
    };
  }

  /// Sends an authenticated request to an AWS service.
  ///
  /// Signs the request using AWS Signature Version 4 and sends it to the specified endpoint.
  /// Supports all HTTP methods including GET, PUT, POST, and DELETE. For PUT and POST requests,
  /// the body parameter will be JSON-encoded and sent with the appropriate content type header.
  ///
  /// Parameters:
  /// - [method]: The HTTP method to use (GET, PUT, POST, DELETE, etc.).
  /// - [uri]: The target URI of an AWS service for the request.
  /// - [headers]: Optional custom headers to include in the request.
  /// - [body]: Optional request body as a map, which will be JSON-encoded.
  ///
  /// Returns the response body as a [String].
  ///
  /// Throws [AWSHttpException] if the response status code indicates an error (not 2xx).
  Future<String> _sendAwsRequest({
    required AWSHttpMethod method,
    required Uri uri,
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    final requestHeaders = <String, String>{...?headers};

    List<int>? bytes;

    if (body != null) {
      requestHeaders.putIfAbsent(
        AWSHeaders.contentType,
        () => 'application/x-amz-json-1.1',
      );
      bytes = json.encode(body).codeUnits;
    }

    final request = AWSHttpRequest(
      method: method,
      uri: uri,
      headers: requestHeaders,
      body: bytes,
    );

    final signedRequest = await _signer.sign(
      request,
      credentialScope: _scope,
      serviceConfiguration: config,
    );
    final operation = signedRequest.send();
    final response = await operation.response;
    final responseBody = await response.decodeBody();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AWSHttpException(
        request,
        'AWS API Error: ${response.statusCode}\nBody: $responseBody',
      );
    }

    return responseBody;
  }

  /// Creates a presigned URL for an AWS request (e.g., S3 GET or PUT).
  ///
  /// Generates a URL with embedded authentication information that allows temporary
  /// access to AWS resources without requiring credentials. Commonly used for generating
  /// download URLs (GET) and upload URLs (PUT) for S3 objects.
  ///
  /// Parameters:
  /// - [method]: The HTTP method the presigned URL is valid for (e.g., GET, PUT).
  /// - [uri]: The target resource URI.
  /// - [expiresIn]: How long the presigned URL remains valid.
  /// - [headers]: Optional headers to include in the signature calculation (e.g., content-type for uploads).
  ///
  /// Returns a presigned [Uri] that can be used to access the resource.
  Future<Uri> createPresignedUrl({
    required AWSHttpMethod method,
    required Uri uri,
    required Duration expiresIn,
    Map<String, String>? headers,
  }) async {
    final request = AWSHttpRequest(method: method, uri: uri, headers: headers);
    return await _signer.presign(
      request,
      credentialScope: _scope,
      expiresIn: expiresIn,
      serviceConfiguration: config,
    );
  }

  /// Sends an authenticated HTTP GET request to the specified URI.
  ///
  /// Parameters:
  /// - [uri]: The target URI for the GET request.
  /// - [headers]: Optional custom headers to include in the request.
  ///
  /// Returns the response body as a [String].
  Future<String> get({required Uri uri, Map<String, String>? headers}) {
    return _sendAwsRequest(method: .get, uri: uri, headers: headers);
  }

  /// Sends an authenticated HTTP PUT request to the specified URI.
  ///
  /// Parameters:
  /// - [uri]: The target URI for the PUT request.
  /// - [headers]: Optional custom headers to include in the request.
  /// - [body]: Optional request body as a map, which will be JSON-encoded.
  ///
  /// Returns the response body as a [String].
  Future<String> put({required Uri uri, Map<String, String>? headers, Map<String, dynamic>? body}) {
    return _sendAwsRequest(method: .put, uri: uri, headers: headers, body: body);
  }

  /// Sends an authenticated HTTP DELETE request to the specified URI.
  ///
  /// Parameters:
  /// - [uri]: The target URI for the DELETE request.
  /// - [headers]: Optional custom headers to include in the request.
  ///
  /// Returns the response body as a [String].
  Future<String> delete({required Uri uri, Map<String, String>? headers}) {
    return _sendAwsRequest(method: .delete, uri: uri, headers: headers);
  }

  /// Sends an authenticated HTTP POST request to the specified URI.
  ///
  /// Commonly used for AWS API operations that require a request body.
  ///
  /// Parameters:
  /// - [uri]: The target URI for the POST request.
  /// - [headers]: Optional custom headers to include in the request.
  /// - [body]: Optional request body as a map, which will be JSON-encoded and sent with content-type 'application/x-amz-json-1.1'.
  ///
  /// Returns the response body as a [String].
  Future<String> post({required Uri uri, Map<String, String>? headers, Map<String, dynamic>? body}) {
    return _sendAwsRequest(method: .post, uri: uri, headers: headers, body: body);
  }
}
