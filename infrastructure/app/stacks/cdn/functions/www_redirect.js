// Viewer request on the web distribution's default behavior: www.<host> is a
// second copy of the site, so it answers with a permanent redirect to the apex
// and search engines index one address. The association files stay served on
// www, since Apple's and Google's fetchers do not follow redirects for them.
function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    if (host.indexOf('www.') !== 0 || request.uri.indexOf('/.well-known/') === 0) {
        return request;
    }

    var query = [];
    for (var name in request.querystring) {
        var param = request.querystring[name];
        var values = param.multiValue ? param.multiValue : [param];
        for (var i = 0; i < values.length; i++) {
            query.push(name + (values[i].value ? '=' + values[i].value : ''));
        }
    }

    var location = 'https://' + host.substring(4) + request.uri;
    if (query.length) {
        location += '?' + query.join('&');
    }

    return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: {location: {value: location}},
    };
}
