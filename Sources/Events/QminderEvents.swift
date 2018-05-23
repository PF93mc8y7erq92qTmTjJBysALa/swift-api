//
//  Events.swift
//  Pods
//
//  Created by Kristaps Grinbergs on 28/10/2016.
//
//

import Foundation

import Starscream

/// Qminder Events works with Qminder Websockets
public class QminderEvents: QminderEventsProtocol {

  public weak var delegate: QminderEventsDelegate?
  
  /// Qminder close code
  fileprivate let websocketReservedCloseCode = UInt16(1099)
  
  /// JSON decoder with milliseconds
  fileprivate let jsonDecoderWithMilliseconds = JSONDecoder.withMilliseconds
  
  /// Websocket message
  fileprivate struct WebsocketMessage {
  
    /// Unique subscribtion ID
    var subscriptionId: String
    
    /// Qminder event
    var eventType: QminderEvent
    
    /// String message what should be sent to Websocket
    var messageToSend: String
    
    /// Callback block
    var callback: Any
  }
  
  /// Message history to hold sent messages to Websocket
  fileprivate var messageHistory = [String]()
  
  /// Message queue to hold not sent messages to Websocket
  fileprivate var messageQueue = [WebsocketMessage]()
  
  /// Callback map type
  fileprivate typealias CallbackMap = (callback: Any, eventType: QminderEvent)
  
  /// Callback map to call specific block when data is received from Websocket
  fileprivate var callbackMap = [String: CallbackMap]()
  
  /// Is currently connection being opened (Boolean)
  fileprivate var openingConnection = false
  
  /// Is connection closed
  fileprivate var connectionClosed = false
  
  /// Websocket object
  fileprivate var socket: WebSocket!
  
  /// Ping queue
  fileprivate let pingQueue = DispatchQueue(label: "com.qminder.pingQueue")
  
  /// Ping interval
  fileprivate let pingInterval = 1
  
  /// Reconnect queue
  fileprivate let reconnectQueue = DispatchQueue(label: "com.qminder.reconnectQueue")
  
  fileprivate let reconnectInterval = 5
  
  /**
    Initialization function. Initializes Websocket object and sets Websocket library delegate to self.
   
    - Parameters:
      - apiKey: Qminder API key
      - serverAddress: Optional server address (used for tests)

    - Returns: Creates Qminder Events client
  */
  public init(apiKey: String, serverAddress: String = "wss://api.qminder.com") {
    self.socket = WebSocket(url: URL(string: "\(serverAddress)/events?rest-api-key=\(apiKey)")!)
    self.socket?.delegate = self
  }
  
  public func openSocket() {
    if !openingConnection {
      print("openSocket")
      openingConnection = true
      connectionClosed = false
      self.socket.connect()
    }
  }
  
  public func reOpenSocket() {
    if !self.socket.isConnected {
      openSocket()
    }
  }
  
  public func closeConnection() {
    messageHistory.removeAll()
    messageQueue.removeAll()
    
    self.connectionClosed = true
    self.socket.disconnect(closeCode: websocketReservedCloseCode)
  }

  public func subscribe(toTicketEvent eventType: QminderEvent,
                        parameters: [String: Any], callback: @escaping EventsCallbackType<Ticket>) {
    
    guard let (message, subscriptionId) = parseParameters(eventType: eventType, parameters: parameters) else {
      callback(Result.failure(QminderError.parse))
      return
    }
    
    sendMessageToWebsocket(subscriptionId: subscriptionId, eventType: eventType, message: message, callback: callback)
  }

  public func subscribe(toDeviceEvent eventType: QminderEvent,
                        parameters: [String: Any], callback: @escaping EventsCallbackType<TVDevice?>) {
    
    guard let (message, subscriptionId) = parseParameters(eventType: eventType, parameters: parameters) else {
      callback(Result.failure(QminderError.parse))
      return
    }
    
    sendMessageToWebsocket(subscriptionId: subscriptionId, eventType: eventType, message: message, callback: callback)
  }
  
  public func subscribe(toLineEvent eventType: QminderEvent,
                        parameters: [String: Any], callback: @escaping EventsCallbackType<[Line]>) {
    
    guard let (message, subscriptionId) = parseParameters(eventType: eventType, parameters: parameters) else {
      callback(Result.failure(QminderError.parse))
      return
    }
    
    sendMessageToWebsocket(subscriptionId: subscriptionId, eventType: eventType, message: message, callback: callback)
  }
  
  /**
   Send message to websocket
   
   - Parameters:
     - subscriptionId: Subscription ID
     - eventType: Qminder event type
     - message: Message to send
     - callback: Callback execute when websocket event has accoured
  */
  private func sendMessageToWebsocket(subscriptionId: String,
                                      eventType: QminderEvent,
                                      message: String,
                                      callback: Any) {
    if socket.isConnected {
      sendMessage(subscriptionId: subscriptionId, eventType: eventType, messageToSend: message, callback: callback)
      
      messageHistory.append(message)
    } else {
      messageQueue.append(WebsocketMessage(subscriptionId: subscriptionId,
                                           eventType: eventType,
                                           messageToSend: message,
                                           callback: callback))
      
      if !openingConnection {
        openSocket()
      }
    }
  }
  
  /**
   Parse parameters
   
   - Parameters:
     - eventType: Qminder event type
     - parameters: Parameters
  */
  private func parseParameters(eventType: QminderEvent,
                               parameters: [String: Any]) -> (message: String, subscriptionId: String)? {
    
    var parameters = parameters
    let subscriptionId = String(withRandomLenght: 30)
    
    parameters["id"] = subscriptionId
    parameters["subscribe"] = eventType.rawValue
    
    do {
      let jsonData = try JSONSerialization.data(withJSONObject: parameters, options: [])
      
      guard let message = String(data: jsonData, encoding: .utf8) else {
        return nil
      }
      
      return (message, subscriptionId)
    } catch {
      return nil
    }
  }
  
  /**
    Send ping
  */
  private func sendPing() {
    guard socket.isConnected else { return }
    
    socket.write(string: "PING")
    
    pingQueue.asyncAfter(deadline: .now() + .seconds(pingInterval)) {[weak self] in
      self?.sendPing()
    }
  }
  
  /**
   Send message to Websocket
   
   - Parameters:
   - subscriptionId: Unique subscription ID
   - messageToSend: Message to send to Websocket
   - callback: Callback block when response is received
   */
  private func sendMessage(subscriptionId: String, eventType: QminderEvent, messageToSend: String, callback: Any) {
    self.callbackMap[subscriptionId] = CallbackMap(callback: callback, eventType: eventType)
    self.socket.write(string: messageToSend)
  }
}

extension QminderEvents: WebSocketDelegate {
  /**
    Delegate methods when websocket did connect
    
    - Parameter socket: Websocket object
  */
  public func websocketDidConnect(socket: WebSocketClient) {
    print("Connection opened")

    openingConnection = false
    
    for message in messageHistory {
      socket.write(string: message)
    }
    
    //send message queue
    while messageQueue.count > 0 {
      let queueItem = messageQueue.removeFirst()

      sendMessage(subscriptionId: queueItem.subscriptionId,
                  eventType: queueItem.eventType,
                  messageToSend: queueItem.messageToSend,
                  callback: queueItem.callback)
      
      messageHistory.append(queueItem.messageToSend)
    }
    
    delegate?.onConnected()
    
    sendPing()
  }
  
  /**
    Delegate method when Websocket did disconnect
    
    - Parameters:
      - socket: Websocket object
      - error: Error why Websocket disconnected
  */
  public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
    openingConnection = false
    
    delegate?.onDisconnected(error: error)
    
    reconnectQueue.asyncAfter(deadline: DispatchTime.now() + .seconds(reconnectInterval), execute: {
      self.reconnect(error: error)
    })
  }
  
  /**
    Delegate function when Websocket received message
    
    - Parameters:
      - socket: Websocket object
      - text: Received text
  */
  public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
    
    guard let data = text.data(using: .utf8) else { return }
    
    do {
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let subscriptionId = json["subscriptionId"] as? String,
        let callbackMap = callbackMap[subscriptionId]
        else { return }
      
      parseWebSocketEvent(with: data, using: callbackMap)
    } catch {
      print("Error deserializing JSON")
    }
  }
  
  /**
   Parse websocket event to Qminder event and execute callback
   
   - Parameters:
     - data: Data to parse from
     - callbackMap: Callback map instance
  */
  private func parseWebSocketEvent(with data: Data, using callbackMap: CallbackMap) {
    switch callbackMap.eventType {
    case .ticketCalled, .ticketCancelled, .ticketCreated, .ticketServed, .ticketChanged, .ticketRecalled:
      
      guard let ticket = try? jsonDecoderWithMilliseconds.decode(TicketEventResponse.self, from: data).data else {
        return
      }
      
      guard let callback = callbackMap.callback as? ((Result<Ticket, QminderError>) -> Void) else { return }
      
      callback(Result<Ticket, QminderError>.success(ticket))
      
    case .overviewMonitorChange:
      let device = try? jsonDecoderWithMilliseconds.decode(DeviceEventResponse.self, from: data).data
      
      guard let callback = callbackMap.callback as? ((Result<TVDevice?, QminderError>) -> Void) else { return }
      
      callback(Result<TVDevice?, QminderError>.success(device))
      
    case .linesChanged:
      guard let lines = try? jsonDecoderWithMilliseconds.decode(LinesEventResponse.self, from: data).lines else {
        return
      }
      
      guard let callback = callbackMap.callback as? ((Result<[Line], QminderError>) -> Void) else { return }
      
      callback(Result<[Line], QminderError>.success(lines))
    }
  }

  /**
    Delegate function when Websocket received data
    
    - Parameters:
      - socket: Websocket object
      - data: Received data
  */
  public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
    print(data)
  }
  
  /**
    Did receive PONG
   
    - Parameters:
      - socket: Websocket
      - data: Data received
  */
  public func websocketDidReceivePong(socket: WebSocketClient, data: Data?) {
    print("Got pong! Maybe some data: \(String(describing: data))")
  }
  
  /**
   Reconnect to Websocket
   
   - Parameters:
   - error: Error
   */
  private func reconnect(error: Error?) {
    
    // If Websocket is closed normally or is connected already
    if connectionClosed || socket.isConnected {
      return
    }
    
    if let error = error as NSError? {
      // Don't reconect if going away normally
      if UInt16(error.code) == websocketReservedCloseCode {
        return
      }
    }
    
    openSocket()
    
    reconnectQueue.asyncAfter(deadline: DispatchTime.now() + .seconds(reconnectInterval), execute: {
      self.reconnect(error: error)
    })
  }
}
