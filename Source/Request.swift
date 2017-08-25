//
//  Request.swift
//  AFBuilder
//
//  Created by Alexander Khmelevsky on 13/03/2017.
//  Copyright © 2017 Alexander Khmelevsky. All rights reserved.
//

import Foundation
import AFNetworking

open class Request {
    
    private var builder: RequestBuilder?
    
    func execute(builder:RequestBuilder) {
        self.builder = builder
        let configurator = builder.configurator
        let manager = builder.manager
        let handlers = configurator.handlers
        
        guard handlers.filter({ !$0.requestShouldStart(builder: builder) }).count == 0 else {
            handlers.forEach({ $0.requestDidFinish(builder:builder) })
            return
        }
        
        handlers.forEach({ $0.requestWillStart(builder:builder) })
        
        for handler in handlers {
            if let error = handler.prepareConfigurator(builder:builder, configurator: configurator) {
                handlers.forEach({ $0.failure(builder:builder, URLSessionDataTask: nil, error: error) })
                handlers.forEach({ $0.requestDidFinish(builder:builder) })
                return
            }
        }
        
        let progress: (Progress) -> Swift.Void = { [weak self] progress in
            guard let builder = self?.builder else { return }
            builder.configurator.handlers.forEach({ $0.progress(builder:builder, progress: progress) })
        }
        
        let headSuccess: (URLSessionDataTask) -> Swift.Void = { [weak self] urlSessionDataTask in
            guard let builder = self?.builder else { return }
            builder.configurator.handlers.forEach({ $0.success(builder:builder, URLSessionDataTask: urlSessionDataTask, result: nil) })
            builder.configurator.handlers.forEach({ $0.requestDidFinish(builder:builder) })
        }
        
        let success: (URLSessionDataTask, Any?) -> Swift.Void = { [weak self] (urlSessionDataTask, responseObject) in
            guard let builder = self?.builder else { return }
            for handler in builder.configurator.handlers {
                if let error = handler.prepareSuccess(builder:builder, URLSessionDataTask: urlSessionDataTask, result: responseObject) {
                    handlers.forEach({ $0.failure(builder:builder, URLSessionDataTask: urlSessionDataTask, error: error) })
                    handlers.forEach({ $0.requestDidFinish(builder:builder) })
                    return
                }
            }
            builder.configurator.handlers.forEach({ $0.success(builder:builder, URLSessionDataTask: urlSessionDataTask, result: responseObject) })
            builder.configurator.handlers.forEach({ $0.requestDidFinish(builder:builder) })
            self?.cleanFromHeap()
        }
        
        let failure: (URLSessionDataTask?, Error) -> Swift.Void = { [weak self] (urlSessionDataTask, error) in
            guard let builder = self?.builder else { return }
            var preparedError = error
            for handler in builder.configurator.handlers {
                preparedError = handler.prepareFailure(builder:builder, URLSessionDataTask:urlSessionDataTask, error:preparedError)
            }
            builder.configurator.handlers.forEach({ $0.failure(builder:builder, URLSessionDataTask: urlSessionDataTask, error: preparedError) })
            builder.configurator.handlers.forEach({ $0.requestDidFinish(builder:builder) })
            self?.cleanFromHeap()
        }
        
        var task: URLSessionDataTask?
        switch configurator.method {
        case .head:   task = manager.head(configurator.urlString, parameters: configurator.params, success: headSuccess, failure: failure)
        case .get:    task = manager.get(configurator.urlString, parameters: configurator.params, progress: progress, success: success, failure: failure)
        case .post:   task = manager.post(configurator.urlString, parameters: configurator.params, progress: progress, success: success, failure: failure)
        case .put:    task = manager.put(configurator.urlString, parameters: configurator.params, success: success, failure: failure)
        case .delete: task = manager.delete(configurator.urlString, parameters: configurator.params, success: success, failure: failure)
        case .patch:  task = manager.patch(configurator.urlString, parameters: configurator.params, success: success, failure: failure)
        case .postMultipartForm(let data): task = manager.post(configurator.urlString, parameters: configurator.params, constructingBodyWith: data, progress: progress, success: success, failure: failure)
        case .multipartFormData(let data): task = manager.post(configurator.urlString, parameters: configurator.params, constructingBodyWith: data, progress: progress, success: success, failure: failure)
        }
        
        self.builder?.task = task
        handlers.forEach({ $0.requestStarted(builder:builder, task: task) })
        Request.heap.append(self)
    }
    
    private static var heap = [Request]()
    private func cleanFromHeap() {
        if let index = Request.heap.index(where: { $0 === self }) { Request.heap.remove(at: index) }
    }
}
