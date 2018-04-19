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
        
        let restartBlock = {
            self.stop()
            DispatchQueue.global().asyncAfter(
                deadline: DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
                    do {
                        try self.start(port, forceIPv4: forceIPv4, priority: priority)
                    } catch {}
            })
        }
        
        DispatchQueue.global(qos: priority).async { [weak self] in
            guard let `self` = self else { return }
            guard self.operating else { return }
            
            //            var master = fd_set()
            //            var read_fds = fd_set()
            
            var poll_set : [pollfd] = []
            //            var numfds : nfds_t = 0
            
            //            fdZero(&master)
            
            //            var fdmax = self.socket.socketFileDescriptor
            
            poll_set.append(pollfd())
            poll_set[0].fd = self.socket.socketFileDescriptor
            poll_set[0].events = Int16(POLLIN)
            //            numfds+=1
            
            //            fdSet(fdmax, set: &master)
            
            while true {
                //                fdZero(&read_fds)
                //                read_fds = master
                #if LOGDEBUG
                print("Waiting for select...")
                #endif
                var timeout = timeval(tv_sec: 3*60, tv_usec: 0)
                //                let result = select(fdmax+1, &read_fds, nil, nil, &timeout)
                let result = poll(&poll_set, nfds_t(poll_set.count), 5000)
                //                if result == 0 {
                ////                    #if LOGDEBUG
                //                        print("Select failed on timeout = \(timeout)")
                ////                    #endif
                //                    continue
                //                } else if result < 0 {
                ////                    #if LOGDEBUG
                //                    print("Select failed on error = \(numfds) - \(errno)")
                ////                    #endif
                //                    restartBlock()
                //                    return
                //                }
                //                print("poll: \(result)")
                
                // run through the existing connections looking for data to read
                //                for i in 0 ..< fdmax+1 {
                for i in 0 ..< poll_set.count {
                    if poll_set[i].revents != 0 && poll_set[i].revents == Int16(POLLIN) {
                        //                    if fdIsSet(i, set: &read_fds) { // we got one!!
                        if poll_set[i].fd == self.socket.socketFileDescriptor {
                            //                        if i == self.socket.socketFileDescriptor {
                            // handle new connections
                            var addr = sockaddr()
                            var len: socklen_t = 0
                            let newfd = accept(self.socket.socketFileDescriptor, &addr, &len)
                            
                            if newfd == -1 {
                                #if LOGDEBUG
                                print("Accept Failed - \(newfd) - \(errno)")
                                #endif
                                restartBlock()
                                return
                            } else {
                                var poll = pollfd()
                                poll.fd = newfd
                                poll.events = Int16(POLLIN)
                                poll_set.append(poll)
                                //                                numfds+=1
                                //                                fdSet(newfd, set: &master) // add to master set
                                //                                if (newfd > fdmax) {    // keep track of the max
                                //                                    fdmax = newfd
                                //                                }
                                #if LOGDEBUG
                                print("\tSelected new connection: \(newfd)")
                                #endif
                            }
                            
                        } else {
                            #if LOGDEBUG
                            print("\tHandle data from the client on \(poll_set[i].fd)")
                            #endif
                            //                            let socket = Socket(socketFileDescriptor: Int32(i))
                            let socket = Socket(socketFileDescriptor: poll_set[i].fd)
                            
                            //                            fdClr(i, set: &master)
                            let position = i
                            poll_set[position].fd = -1
                            self.handleConnection(socket: socket) { socket, keepConnection in
                                #if LOGDEBUG
                                print("\tReturned from the client on \(poll_set[position].fd) - keep connection: \(keepConnection)")
                                #endif
                                if !keepConnection {
                                    socket.close()
                                    poll_set[position].fd = -1
                                    poll_set[position].events = 0
                                    poll_set[position].revents = 0
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
                            #if LOGDEBUG
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
