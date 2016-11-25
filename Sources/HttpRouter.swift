//
//  HttpRouter.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

public protocol HttpRoute: class {
    func dispatch(request: HttpRequest, completion: (([String: String], HttpRequest -> HttpResponse) -> Void)) -> Bool
}

public class HttpCallbackRoute: HttpRoute {
    
    private let callback: (HttpRequest -> HttpResponse)
    
    public init(callback: (HttpRequest -> HttpResponse)) {
        self.callback = callback
    }
    
    public func dispatch(request: HttpRequest,
                  completion: (([String: String], HttpRequest -> HttpResponse) ->
        Void)) -> Bool {
        let params: [String: String] = [:]
        completion(params, callback)
        return true
    }
}

public class HttpRouter: HttpRoute {
    
    private class Node {
        var nodes = [String: Node]()
        var handler: HttpRoute? = nil
    }
    
    private var rootNode = Node()

    public func routes() -> [String] {
        var routes = [String]()
        for (_, child) in rootNode.nodes {
            routes.appendContentsOf(routesForNode(child));
        }
        return routes
    }
    
    private func routesForNode(node: Node, prefix: String = "") -> [String] {
        var result = [String]()
        if let _ = node.handler {
            result.append(prefix)
        }
        for (key, child) in node.nodes {
            result.appendContentsOf(routesForNode(child, prefix: prefix + "/" + key));
        }
        return result
    }
    
    public func register(method: String?, path: String, callback: (HttpRequest -> HttpResponse)?) {
        if callback != nil {
            register(method, path: path, handler: HttpCallbackRoute(callback: callback!))
        } else {
            register(method, path: path, handler: nil)
        }
    }
    
    public func register(method: String?, path: String, handler: HttpRoute?) {
        var pathSegments = stripQuery(path).split("/")
        if let method = method {
            pathSegments.insert(method, atIndex: 0)
        } else {
            pathSegments.insert("*", atIndex: 0)
        }
        var pathSegmentsGenerator = pathSegments.generate()
        let node = inflate(&rootNode, generator: &pathSegmentsGenerator)
        node.handler = handler
    }
    
    public func dispatch(request: HttpRequest, completion: (([String : String], HttpRequest -> HttpResponse) -> Void)) -> Bool {
        let method = request.method
        let path = request.path

        let pathSegments = (method + "/" + stripQuery(path)).split("/")
        var pathSegmentsGenerator = pathSegments.generate()
        var params = [String:String]()
        if let handler = findHandler(&rootNode, params: &params, generator: &pathSegmentsGenerator) {
            handler.dispatch(request, completion: completion)
            return true
        } else {
            let pathSegments = ("*/" + stripQuery(path)).split("/")
            var pathSegmentsGenerator = pathSegments.generate()
            var params = [String:String]()
            if let handler = findHandler(&rootNode, params: &params, generator: &pathSegmentsGenerator) {
                handler.dispatch(request, completion: completion)
                return true
            } else {
                return false
            }
        }
    }
    
    private func inflate(inout node: Node, inout generator: IndexingGenerator<[String]>) -> Node {
        if let pathSegment = generator.next() {
            if let _ = node.nodes[pathSegment] {
                return inflate(&node.nodes[pathSegment]!, generator: &generator)
            }
            var nextNode = Node()
            node.nodes[pathSegment] = nextNode
            return inflate(&nextNode, generator: &generator)
        }
        return node
    }
    
    private func findHandler(inout node: Node, inout params: [String: String], inout generator: IndexingGenerator<[String]>) -> HttpRoute? {
        guard let pathToken = generator.next() else {
            return node.handler
        }
        let variableNodes = node.nodes.filter { $0.0.characters.first == ":" }
        if let variableNode = variableNodes.first {
            if variableNode.1.nodes.count == 0 {
                // if it's the last element of the pattern and it's a variable, stop the search and
                // append a tail as a value for the variable.
                let tail = generator.joinWithSeparator("/")
                if tail.utf8.count > 0 {
                    params[variableNode.0] = pathToken + "/" + tail
                } else {
                    params[variableNode.0] = pathToken
                }
                return variableNode.1.handler
            }
            params[variableNode.0] = pathToken
            return findHandler(&node.nodes[variableNode.0]!, params: &params, generator: &generator)
        }
        if var node = node.nodes[pathToken] {
            return findHandler(&node, params: &params, generator: &generator)
        }
        if var node = node.nodes["*"] {
            return findHandler(&node, params: &params, generator: &generator)
        }
        return nil
    }
    
    private func stripQuery(path: String) -> String {
        if let path = path.split("?").first {
            return path
        }
        return path
    }
}
