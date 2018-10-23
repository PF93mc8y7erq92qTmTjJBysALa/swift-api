//
//  Extensions+Data.swift
//  QminderAPI
//
//  Created by Kristaps Grinbergs on 09/03/2018.
//  Copyright © 2018 Kristaps Grinbergs. All rights reserved.
//

import Foundation

extension Data {
  
  /**
   Decode response data with data container
   
   - Parameters:
     - decodingType: Decoding type
   
   - Returns: Result enum
  */
  func decode<T: ResponsableWithData>(_ decodingType: T.Type) -> QminderResult<T.Data, QminderError> {
    do {
      return try QminderResult(JSONDecoder.withMilliseconds.decode(decodingType, from: self).dataObject)
    } catch {
      return QminderResult(QminderError.jsonParsing(error))
    }
  }
  
  /**
   Decode response data without data container
   
   - Parameters:
   - decodingType: Decoding type
   
   - Returns: Result enum
   */
  func decode<T: Responsable>(_ decodingType: T.Type) -> QminderResult<T, QminderError> {
    do {
      return try QminderResult(JSONDecoder.withMilliseconds.decode(decodingType, from: self))
    } catch {
      return QminderResult(QminderError.jsonParsing(error))
    }
  }
}
