function handler(event) {
  var request = event.request;
  var parts;
  try {
    parts = decodeURIComponent(request.uri).split('/');
  } catch (error) {
    return { statusCode: 403, statusDescription: 'Forbidden' };
  }
  var path = [];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === '..') path.pop();
    else if (parts[i] !== '' && parts[i] !== '.') path.push(parts[i]);
  }
  if (['imports', 'exports', 'uploads', 'exercise-uploads'].indexOf(path[0]) !== -1) {
    return {
      statusCode: 403,
      statusDescription: 'Forbidden',
      headers: { 'cache-control': { value: 'no-store' } }
    };
  }
  return request;
}
