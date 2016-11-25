//
//  HttpServer.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

public class HttpServer: HttpServerIO {
    
    public static let VERSION = "1.2.6"
    
    private let router = HttpRouter()
    
    public override init() {
        self.DELETE = MethodRoute(method: "DELETE", router: router)
        self.UPDATE = MethodRoute(method: "UPDATE", router: router)
        self.HEAD   = MethodRoute(method: "HEAD", router: router)
        self.POST   = MethodRoute(method: "POST", router: router)
        self.GET    = MethodRoute(method: "GET", router: router)
        self.PUT    = MethodRoute(method: "PUT", router: router)
        
        self.delete = MethodRoute(method: "DELETE", router: router)
        self.update = MethodRoute(method: "UPDATE", router: router)
        self.head   = MethodRoute(method: "HEAD", router: router)
        self.post   = MethodRoute(method: "POST", router: router)
        self.get    = MethodRoute(method: "GET", router: router)
        self.put    = MethodRoute(method: "PUT", router: router)
    }
    
    public var DELETE, UPDATE, HEAD, POST, GET, PUT : MethodRoute
    public var delete, update, head, post, get, put : MethodRoute
    
    public subscript(path: String) -> (HttpRequest -> HttpResponse)? {
        set {
            router.register(nil, path: path, callback: newValue)
        }
        get { return nil }
    }
    
    public var routes: [String] {
        return router.routes();
    }
    
    public var notFoundHandler: HttpRoute?
    
    public var middleware = Array<(HttpRequest) -> HttpResponse?>()

    public override func dispatch(request: HttpRequest,
                                  completion: (([String : String], HttpRequest -> HttpResponse) -> Void)) {
        
        for layer in middleware {
            if let response = layer(request) {
                completion([:], { _ in response })
                return
            }
        }
    
        if self.router.dispatch(request, completion: completion) {
            return
        } else if let notFoundHandler = self.notFoundHandler where notFoundHandler.dispatch(request, completion: completion) {
            return
        } else {
            super.dispatch(request, completion: completion)
        }
    }
    
    public struct MethodRoute {
        public let method: String
        public let router: HttpRouter
        public subscript(path: String) -> (HttpRequest -> HttpResponse)? {
            set {
                router.register(method, path: path, callback: newValue)
            }
            get { return nil }
        }
    }
}
