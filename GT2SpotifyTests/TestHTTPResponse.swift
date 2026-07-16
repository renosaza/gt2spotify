import Foundation

func response(
    _ request: URLRequest,
    status: Int,
    headers: [String: String]? = nil,
    body: String = ""
) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
    return (response, Data(body.utf8))
}
