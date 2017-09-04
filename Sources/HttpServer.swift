//
//  HttpServer.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

public class HttpServer: HttpServerIO {
    
    public static let VERSION = "1.3.2"
    
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
    
    public subscript(path: String) -> ((HttpRequest) -> HttpResponse)? {
        set {
            router.register(method: nil, path: path, callback: newValue)
        }
        get { return nil }
    }
    
    public var routes: [String] {
        return router.routes();
    }
    
    public var notFoundHandler: HttpRoute?
    
    public var middleware = Array<(HttpRequest) -> HttpResponse?>()

    public override func dispatch(request: HttpRequest,
                                  completion: @escaping (([String : String], (HttpRequest) -> HttpResponse) -> Void)) {

        for layer in middleware {
            if let response = layer(request) {
                completion([:], { _ in response })
                return
            }
        }
        
        if self.router.dispatch(request: request, completion: completion) {
            return
        } else if let notFoundHandler = self.notFoundHandler, notFoundHandler.dispatch(request: request, completion: completion) {
            return
        } else {
            super.dispatch(request: request, completion: completion)
        }
    }
    
    public override func cancel(request : HttpRequest) {
        if let notFoundHandler = self.notFoundHandler {
            notFoundHandler.cancel(request: request)
        } else {
            self.router.cancel(request: request)
        }
    }
    
    public struct MethodRoute {
        public let method: String
        public let router: HttpRouter
        public subscript(path: String) -> ((HttpRequest) -> HttpResponse)? {
            set {
                router.register(method: method, path: path, callback: newValue)
            }
            get { return nil }
        }
    }
}
