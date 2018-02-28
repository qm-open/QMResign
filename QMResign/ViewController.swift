//
//  ViewController.swift
//  QMResign
//
//
// Copyright (c) 2018 Quickmobile
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Cocoa

class ViewController: NSViewController, NSTextFieldDelegate, NSComboBoxDelegate, NSComboBoxDataSource {

    @objc dynamic var isRunning = false
    var outputPipe:Pipe!
    var buildTask:Process!
    var selectedIPA: Bool!
    var selectedProvisioningProfile: Bool!
    var defaults: UserDefaults!
    fileprivate var certificates:[String] = []

    
    @IBOutlet weak var pathIPA: NSPathControl!
    @IBOutlet weak var pathProvisioningProfile: NSPathControl!
    @IBOutlet weak var comboCodeSignIdentity: NSComboBox!
    @IBOutlet weak var buttonSelectIPA: NSButton!
    @IBOutlet weak var buttonSelectProvisioningProfile: NSButton!

    @IBOutlet weak var butonResign: NSButton!
    @IBOutlet var outputText: NSTextView!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    @IBAction func onSelectPathIPA(_ sender: Any) {
        
        if let selectedUrl = NSOpenPanel().selectIPA {
            pathIPA.url = selectedUrl;
            print("IPA selected:", selectedUrl.path)
            selectedIPA = true
        } else {
            print("IPA selection was canceled")
        }
    }

    @IBAction func onSelectPathProvisioningProfile(_ sender: Any) {
        
        if let selectedUrl = NSOpenPanel().selectProvisioningProfile {
            pathProvisioningProfile.url = selectedUrl;
            print("Provisioning Profile selected:", selectedUrl.path)
            selectedProvisioningProfile = true
        } else {
            print("Provisioning Profile selection was canceled")
        }
    }

    @IBAction func onResignIPA(_ sender: Any) {
        
        guard selectedIPA == true else {
            let alert = NSAlert()
            alert.addButton(withTitle: "OK")
            alert.informativeText = "Please select an IPA to re-sign"
            alert.messageText = "No IPA selected"
            alert.runModal()

            return
        }

        guard selectedProvisioningProfile == true else {
            let alert = NSAlert()
            alert.addButton(withTitle: "OK")
            alert.informativeText = "Please select a Provisioning Profile to use during resign process"
            alert.messageText = "No Provisioning Profile selected"
            alert.runModal()
            
            return
        }

        
        if let urlIPA = pathIPA.url, let urlProvisioningProfile = pathProvisioningProfile.url {
            
            let pathToIPA = urlIPA.standardizedFileURL.deletingLastPathComponent().path
            let pathProvisioningProfile = urlProvisioningProfile.standardizedFileURL.path
            let signingIdentigy = comboCodeSignIdentity.stringValue
            let fileNameIPA = urlIPA.standardizedFileURL.lastPathComponent

            var arguments:[String] = []
            arguments.append(signingIdentigy)
            arguments.append(pathProvisioningProfile)
            arguments.append(fileNameIPA)
            
            butonResign.isEnabled = false
            buttonSelectIPA.isEnabled = false
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(self)
            
            
            outputText.textStorage?.mutableString.setString("")
            runScript(path: pathToIPA, args: arguments)
        }
        else {
            let alert = NSAlert()
            alert.addButton(withTitle: "OK")
            alert.messageText = "Select a valid IPA"
            alert.informativeText = "Used in re-signing process"
            
            let _ = alert.runModal()
        }
    }
    
    @IBAction func onStopResignTask(_ sender:AnyObject) {
        
        if isRunning {
            buildTask.terminate()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        selectedIPA = false
        selectedProvisioningProfile = false
        loadCertificates()

        defaults = UserDefaults()
        let id = defaults.value(forKey: "SIGNING_IDENTITY") as? String
        if let signingIdentiy = id {
            comboCodeSignIdentity.stringValue = signingIdentiy
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func runScript(path: String, args:[String]) {
        
        isRunning = true
        let taskQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
        taskQueue.async {
            
            guard let scriptPath = Bundle.main.path(forResource: "ResignScript",ofType:"command") else {
                print("Unable to locate ResignScript.command")
                return
            }
            
            print("path:\(path)")

            self.buildTask = Process()
            self.buildTask.launchPath = scriptPath
            self.buildTask.arguments = args
            self.buildTask.currentDirectoryPath = path

            self.buildTask.terminationHandler = {
                
                task in
                DispatchQueue.main.async(execute: {
                    self.butonResign.isEnabled = true
                    self.buttonSelectIPA.isEnabled = true
                    self.progressIndicator.isHidden = true
                    self.progressIndicator.stopAnimation(self)
                    self.isRunning = false
                })
                
            }
            
            self.captureStandardOutputAndRouteToTextView(self.buildTask)
            self.buildTask.launch()
            self.buildTask.waitUntilExit()
        }
    }
    
    func captureStandardOutputAndRouteToTextView(_ task:Process) {
        
        outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSFileHandleDataAvailable, object: outputPipe.fileHandleForReading , queue: nil) {
            notification in
            
            let output = self.outputPipe.fileHandleForReading.availableData
            let outputString = String(data: output, encoding: String.Encoding.utf8) ?? ""
            
            DispatchQueue.main.async(execute: {
                let previousOutput = self.outputText.string
                let nextOutput = previousOutput + "\n" + outputString
                self.outputText.string = nextOutput
                
                let range = NSRange(location:nextOutput.count,length:0)
                self.outputText.scrollRangeToVisible(range)
                
            })
            
            self.outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
            
            
        }
        
    }
    
    
    // MARK: - Certificates
    
    private func loadCertificates() {
        DispatchQueue.global().async {
            
            let task:Process = Process()
            let pipe:Pipe = Pipe()
            
            task.launchPath = "/usr/bin/security"
            task.arguments = ["find-identity", "-v", "-p", "codesigning"]
            task.standardOutput = pipe
            task.standardError = pipe
            
            let handle = pipe.fileHandleForReading
            task.launch()
            
            let data = handle.readDataToEndOfFile()
            self.parseCertificatesFrom(data: data)
        }
    }
    
    private func parseCertificatesFrom(data: Data) {
        let buffer = String(data: data, encoding: String.Encoding.utf8)!
        var names:[String] = []
        
        buffer.enumerateLines { (line, _) in
            // default output line format for security command:
            // 1) E00D4E3D3272ABB655CDE0C1CF53891210BAF4B8 "iPhone Developer: XXXXXXXXXX (YYYYYYYYYY)"
            let components = line.components(separatedBy: "\"")
            if components.count > 2 {
                let commonName = components[components.count - 2]
                names.append(commonName)
            }
        }
        
        names.sort(by: { $0 < $1 })
        DispatchQueue.main.sync {
            self.certificates.removeAll()
            self.certificates.append(contentsOf: names)
            self.comboCodeSignIdentity.reloadData()
        }
    }
    
    // MARK - NSTextFieldDelegate
    
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        return true
    }
    
    override func controlTextDidBeginEditing(_ obj: Notification) {
        
    }
    
    override func controlTextDidEndEditing(_ obj: Notification) {
        
    }
    
    // MARK: - NSComboBoxDataSource

    func numberOfItems(in comboBox: NSComboBox) -> Int {
        return certificates.count
    }
    
    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        return certificates[index]
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        
        if let comboBox = notification.object as? NSComboBox {
            let signingIdentity =  certificates[comboBox.indexOfSelectedItem]
            defaults.set(signingIdentity, forKey: "SIGNING_IDENTITY")
        }
    }
}

