// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Atomics

public class CircularBuffer<DataType> {
    
    public enum Error: Swift.Error {
        case invalidCount(Int)
        case insufficientSpace(available: Int, requested: Int)
        case insufficientData(available: Int, requested: Int)
    }
    
    private let capacity: Int
    
    private var buffers: [DataType]
    
    private let writeHead: ManagedAtomic<UInt64> = .init(0)
    private let readHead: ManagedAtomic<UInt64> = .init(0)
    
    public var approximateCount: Int {
        Int(writeHead.load(ordering: .relaxed) - readHead.load(ordering: .relaxed))
    }
    
    public init(repeating value: DataType, capacity: Int) {
        precondition(capacity > 0, "Capacity must be greater than 0")
        self.capacity = capacity
        self.buffers = Array(repeating: value, count: capacity)
    }
    
    public func write(from data: [DataType]) throws {
        try data.withUnsafeBufferPointer { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else {
                return
            }
            try write(from: baseAddress, count: bufferPointer.count)
        }
    }
    
    public func write(from data: UnsafePointer<DataType>, count: Int) throws {
        guard count > 0 else {
            throw Error.invalidCount(count)
        }
        
        let w = writeHead.load(ordering: .relaxed)
        let r = readHead.load(ordering: .acquiring)
        let available = UInt64(capacity) - (w - r)
        
        guard available >= count else {
            throw Error.insufficientSpace(available: Int(available), requested: count)
        }
        
        let startIndex = Int(w % UInt64(capacity))
        let _count = min(count, capacity - Int(startIndex))
        buffers.withUnsafeMutableBufferPointer { bufferPointer in
            guard let base = bufferPointer.baseAddress else {
                return
            }
            base.advanced(by: startIndex)
                .update(from: data, count: _count)
            let remaining = count - _count
            if remaining > 0 {
                base.update(from: data.advanced(by: _count), count: remaining)
            }
        }
        
        writeHead.store(w + UInt64(count), ordering: .releasing)
    }
    
    public func read(into data: UnsafeMutablePointer<DataType>, count: Int) throws {
        guard count > 0 else {
            throw Error.invalidCount(count)
        }
        
        let w = writeHead.load(ordering: .acquiring)
        let r = readHead.load(ordering: .relaxed)
        let available = w - r
        
        guard available >= count else {
            throw Error.insufficientData(available: Int(available), requested: count)
        }
        
        let startIndex = Int(r % UInt64(capacity))
        let _count = min(count, capacity - startIndex)
        buffers.withUnsafeBufferPointer { bufferPointer in
            guard let base = bufferPointer.baseAddress else {
                return
            }
            data.update(from: base.advanced(by: startIndex), count: _count)
            let remaining = count - _count
            if remaining > 0 {
                data.advanced(by: _count).update(from: base, count: remaining)
            }
        }
        
        readHead.store(r + UInt64(count), ordering: .releasing)
    }
    
}
