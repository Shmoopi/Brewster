//
//  AppDelegate.swift
//  Brewster
//
//  Created by Shmoopi LLC
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    // statusBarController
    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        // Init the statusBarController
        statusBarController = StatusBarController()
    }
    
}
