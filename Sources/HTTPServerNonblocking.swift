//
//  HTTPServerNonblocking.swift
//  Swifter
//
//  Created by Ronaldo Junior on 8/10/17.
//  Copyright © 2017 Damian Kołakowski. All rights reserved.
//

import Foundation

public class HTTPServerNonblocking: HttpServer {

    public override init() {
    }
    
    public override func start(_ port: in_port_t = 8080, forceIPv4: Bool = false, priority: DispatchQoS.QoSClass = DispatchQoS.QoSClass.background) throws {
        guard !self.operating else { return }
        stop()
        self.state = .starting
        let address = forceIPv4 ? listenAddressIPv4 : listenAddressIPv6
        self.socket = try Socket.tcpSocketForListen(port, forceIPv4, SOMAXCONN, address, true)
        DispatchQueue.global(qos: priority).async { [weak self] in
            guard let `self` = self else { return }
            guard self.operating else { return }
            
            var master = fd_set()
            var read_fds = fd_set()
            
            fdZero(&master)
            
            var fdmax = self.socket.socketFileDescriptor
            
            fdSet(fdmax, set: &master)
            
            while true {
                fdZero(&read_fds)
                read_fds = master
                #if DEBUG
                    print("Waiting for select...")
                #endif
                var timeout = timeval(tv_sec: 3*60, tv_usec: 0)
                if select(fdmax+1, &read_fds, nil, nil, &timeout) == -1 {
                    #if DEBUG
                        print("Select failed = \(timeout)")
                    #endif
                    continue
                }
                
                // run through the existing connections looking for data to read
                for i in 0 ..< fdmax+1 {
                    if fdIsSet(i, set: &read_fds) { // we got one!!
                        if i == self.socket.socketFileDescriptor {
                            // handle new connections
                            var addr = sockaddr()
                            var len: socklen_t = 0
                            let newfd = accept(self.socket.socketFileDescriptor, &addr, &len)
                            
                            if newfd == -1 {
                                #if DEBUG
                                    print("Accept Failed")
                                #endif
                                self.stop()
                                DispatchQueue.main.asyncAfter(
                                    deadline: DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
                                        do {
                                            try self.start(port, forceIPv4: forceIPv4, priority: priority)
                                        } catch {}
                                })
                                return
                            } else {
                                fdSet(newfd, set: &master); // add to master set
                                if (newfd > fdmax) {    // keep track of the max
                                    fdmax = newfd;
                                }
                                #if DEBUG
                                    print("\tSelected new connection: \(newfd)")
                                #endif
                            }
                            
                        } else {
                            #if DEBUG
                                print("\tHandle data from the client on \(i)")
                            #endif
                            let socket = Socket(socketFileDescriptor: i)
                            
                            fdClr(i, set: &master)
                            self.handleConnection(socket: socket) { socket, keepConnection in
                                #if DEBUG
                                    print("\tReturned from the client on \(i) - keep connection: \(keepConnection)")
                                #endif
                                if !keepConnection {
                                    socket.close()
                                }
                            }
                            
                        } // END handle data from client
                    } // END got new incoming connection
                } // END looping through file descriptors
            } // END for(;;)--and you thought it would never end!
        }
        self.state = .running
    }
        
    private func handleConnection(socket: Socket, completion: @escaping ((_ socket : Socket, _ keepConnection: Bool) -> Void)) {
        
        let parser = HttpParser()
        
        if self.operating, let request = try? parser.readHttpRequest(socket) {
            request.address = try? socket.peername()
            dispatch(request: request, completion: { (params, handler) in
                request.params = params
                let response = handler(request)
                DispatchQueue.global().async {
                    let range = response.headers()["Range"]
                    var keepConnection = parser.supportsKeepAlive(request.headers)
                    do {
                        if self.operating {
                            #if DEBUG
                                print("\t\tResponse on - \(socket.socketFileDescriptor) - \(request.path) - \(range ?? "") - \(response.statusCode())")
                            #endif
                            keepConnection = try self.respond(socket, response: response, keepAlive: keepConnection)
                        }
                    } catch {
                        self.cancel(request: request)
                        completion(socket, false)
                        return
                    }
                    
                    if let session = response.socketSession() {
                        session(socket)
                        completion(socket, keepConnection)
                    }
                    
                    if keepConnection || response.statusCode() == 206 {
                        completion(socket, true)
                    } else {
                        socket.close()
                        completion(socket, false)
                    }
                }
            })
        } else {
            completion(socket, false)
        }
    }

}

////////////////////////////////////////////////////////////////////////////////////////////////
//Information: code for manually reading socket data instead of using handleConnection method:
////////////////////////////////////////////////////////////////////////////////////////////////
//
//                            // handle data from a client
//                            var buffer = [UInt8](repeating: 0, count: 1)
//                            let nbytes = recv(i as Int32, &buffer, Int(buffer.count), 0)
//                            if nbytes <= 0 {
//                                // got error or connection closed by client
//                                if (nbytes == 0) {
//                                    // connection closed
//                                    print("Connection closed on \(i)")
//                                } else {
//                                    print("Recv failed")
//                                }
//                                close(i) // bye!
//                                fdClr(i, set: &master)
//                            } else {
//                                // we got some data from a client
//                                for j in 0 ..< fdmax {
//                                    // send to everyone!
//                                    if fdIsSet(j, set: &master) {
//                                        // except the listener and ourselves
//                                        if j != self.socket.socketFileDescriptor && j != i {
//                                            if send(j, buffer, nbytes, 0) == -1 {
//                                                print("Send failed");
//                                            }
//                                        }
//                                    }
//                                }
//                            }
