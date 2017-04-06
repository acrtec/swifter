//
//  HttpRouter.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation


public protocol HttpRoute: class {
    func dispatch(request: HttpRequest, completion: @escaping (([String: String], (HttpRequest) -> HttpResponse) -> Void)) -> Bool
}

open class HttpCallbackRoute: HttpRoute {
    
    private let callback: ((HttpRequest) -> HttpResponse)
    
    public init(callback: @escaping ((HttpRequest) -> HttpResponse)) {
        self.callback = callback
    }
    
    public func dispatch(request: HttpRequest,
                         completion: @escaping (([String: String], (HttpRequest) -> HttpResponse) ->
        Void)) -> Bool {
        let params: [String: String] = [:]
        completion(params, callback)
        return true
    }
}

open class HttpRouter: HttpRoute {
    
    public init() {
    }
    
    private class Node {
        var nodes = [String: Node]()
        var handler: HttpRoute? = nil
    }
    
    private var rootNode = Node()

    public func routes() -> [String] {
        var routes = [String]()
        for (_, child) in rootNode.nodes {
            routes.append(contentsOf: routesForNode(child));
        }
        return routes
    }
    
    private func routesForNode(_ node: Node, prefix: String = "") -> [String] {
        var result = [String]()
        if let _ = node.handler {
            result.append(prefix)
        }
        for (key, child) in node.nodes {
            result.append(contentsOf: routesForNode(child, prefix: prefix + "/" + key));
        }
        return result
    }
    
    public func register(method: String?, path: String, callback: ((HttpRequest) -> HttpResponse)?) {
        if callback != nil {
            register(method: method, path: path, handler: HttpCallbackRoute(callback: callback!))
        } else {
            register(method: method, path: path, handler: nil)
        }
    }
    
    public func register(method: String?, path: String, handler: HttpRoute?) {
        var pathSegments = stripQuery(path).split("/")
        if let method = method {
            pathSegments.insert(method, at: 0)
        } else {
            pathSegments.insert("*", at: 0)
        }
        var pathSegmentsGenerator = pathSegments.makeIterator()
        let node = inflate(&rootNode, generator: &pathSegmentsGenerator)
        node.handler = handler
    }
    
    public func dispatch(request: HttpRequest, completion: @escaping (([String : String], (HttpRequest) -> HttpResponse) -> Void)) -> Bool {
        let method = request.method
        let path = request.path
        
        let pathSegments = (method + "/" + stripQuery(path)).split("/")
        var pathSegmentsGenerator = pathSegments.makeIterator()
        var params = [String:String]()
        if let handler = findHandler(node: &rootNode, params: &params, generator: &pathSegmentsGenerator) {
            let _ = handler.dispatch(request: request, completion: completion)
            return true
        } else {
            let pathSegments = ("*/" + stripQuery(path)).split("/")
            var pathSegmentsGenerator = pathSegments.makeIterator()
            var params = [String:String]()
            if let handler = findHandler(node: &rootNode, params: &params, generator: &pathSegmentsGenerator) {
                let _ = handler.dispatch(request: request, completion: completion)
                return true
            } else {
                return false
            }
        }
    }
    
    private func inflate(_ node: inout Node, generator: inout IndexingIterator<[String]>) -> Node {
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
    
    private func findHandler( node: inout Node, params: inout [String: String], generator: inout IndexingIterator<[String]>) -> HttpRoute? {
        guard let pathToken = generator.next() else {
            // if it's the last element of the requested URL, check if there is a pattern with variable tail.
            if let variableNode = node.nodes.filter({ $0.0.characters.first == ":" }).first {
                if variableNode.value.nodes.isEmpty {
                    params[variableNode.0] = ""
                    return variableNode.value.handler
                }
            }
            return node.handler
        }
        let variableNodes = node.nodes.filter { $0.0.characters.first == ":" }
        if let variableNode = variableNodes.first {
            if variableNode.1.nodes.count == 0 {
                // if it's the last element of the pattern and it's a variable, stop the search and
                // append a tail as a value for the variable.
                let tail = generator.joined(separator: "/")
                if tail.characters.count > 0 {
                    params[variableNode.0] = pathToken + "/" + tail
                } else {
                    params[variableNode.0] = pathToken
                }
                return variableNode.1.handler
            }
            params[variableNode.0] = pathToken
            return findHandler(node: &node.nodes[variableNode.0]!, params: &params, generator: &generator)
        }
        if var node = node.nodes[pathToken] {
            return findHandler(node: &node, params: &params, generator: &generator)
        }
        if var node = node.nodes["*"] {
            return findHandler(node: &node, params: &params, generator: &generator)
        }
        if let startStarNode = node.nodes["**"] {
            let startStarNodeKeys = startStarNode.nodes.keys
            while let pathToken = generator.next() {
                if startStarNodeKeys.contains(pathToken) {
                    return findHandler(node: &startStarNode.nodes[pathToken]!, params: &params, generator: &generator)
                }
            }
        }
        return nil
    }
    
    private func stripQuery(_ path: String) -> String {
        if let path = path.components(separatedBy: "?").first {
            return path
        }
        return path
    }
}

extension String {
    
    public func split(_ separator: Character) -> [String] {
        return self.characters.split { $0 == separator }.map(String.init)
    }
    
}
