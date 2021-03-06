//
//  SwiftyTokeniser.swift
//  SwiftyMarkdown
//
//  Created by Anthony Keller on 09/15/2020.
//  Copyright © 2020 Voyage Travel Apps. All rights reserved.
//
import Foundation
import os.log

extension OSLog {
	private static var subsystem = "SwiftyTokeniser"
	static let tokenising = OSLog(subsystem: subsystem, category: "Tokenising")
	static let styling = OSLog(subsystem: subsystem, category: "Styling")
	static let performance = OSLog(subsystem: subsystem, category: "Peformance")
}

public class SwiftyTokeniser {
	let rules : [CharacterRule]
	var replacements : [String : [Token]] = [:]
	
	var enableLog = (ProcessInfo.processInfo.environment["SwiftyTokeniserLogging"] != nil)
	let totalPerfomanceLog = PerformanceLog(with: "SwiftyTokeniserPerformanceLogging", identifier: "Tokeniser Total Run Time", log: OSLog.performance)
	let currentPerfomanceLog = PerformanceLog(with: "SwiftyTokeniserPerformanceLogging", identifier: "Tokeniser Current", log: OSLog.performance)
		
	public var metadataLookup : [String : String] = [:]
	
	let newlines = CharacterSet.newlines
	let spaces = CharacterSet.whitespaces

	
	public init( with rules : [CharacterRule] ) {
		self.rules = rules
		
		self.totalPerfomanceLog.start()
	}
	
	deinit {
		self.totalPerfomanceLog.end()
	}
	
	
	/// This goes through every CharacterRule in order and applies it to the input string, tokenising the string
	/// if there are any matches.
	///
	/// The for loop in the while loop (yeah, I know) is there to separate strings from within tags to
	/// those outside them.
	///
	/// e.g. "A string with a \[link\]\(url\) tag" would have the "link" text tokenised separately.
	///
	/// This is to prevent situations like **\[link**\](url) from returing a bold string.
	///
	/// - Parameter inputString: A string to have the CharacterRules in `self.rules` applied to
	public func process( _ inputString : String ) -> [Token] {
		let currentTokens = [Token(type: .string, inputString: inputString)]
		guard rules.count > 0 else {
			return currentTokens
		}
		var mutableRules = self.rules
		
		if inputString.isEmpty {
			return [Token(type: .string, inputString: "", characterStyles: [])]
		}
		
		self.currentPerfomanceLog.start()
	
		var elementArray : [Element] = []
		for char in inputString {
			if newlines.containsUnicodeScalars(of: char) {
				let element = Element(character: char, type: .newline)
				elementArray.append(element)
				continue
			}
			if spaces.containsUnicodeScalars(of: char) {
				let element = Element(character: char, type: .space)
				elementArray.append(element)
				continue
			}
			let element = Element(character: char, type: .string)
			elementArray.append(element)
		}
		
		while !mutableRules.isEmpty {
			let nextRule = mutableRules.removeFirst()
			if enableLog {
				os_log("------------------------------", log: .tokenising, type: .info)
				os_log("RULE: %@", log: OSLog.tokenising, type:.info , nextRule.description)
			}
			self.currentPerfomanceLog.tag(with: "(start rule %@)")
			
			let scanner = SwiftyScanner(withElements: elementArray, rule: nextRule, metadata: self.metadataLookup)
			elementArray = scanner.scan()
		}
		
		var output : [Token] = []
		var lastElement = elementArray.first!
		
		func empty( _ string : inout String, into tokens : inout [Token] ) {
			guard !string.isEmpty else {
				return
			}

            if let index = lastElement.styles.firstIndex(where: { $0.isEqualTo(CharacterStyle.mention) || $0.isEqualTo(CharacterStyle.mentionAll)}) {
                if let metadataRange = string.range(of: #"^([0-9]+)"#, options: .regularExpression) {
                    lastElement.metadata.append(String(string[metadataRange]))

                    if let metadataRange = string.range(of: #"^([0-9]+:[0-9]+\})"#, options: .regularExpression) {
                        string = "@@" + String(string.suffix(from: metadataRange.upperBound))
                        lastElement.styles[index] = CharacterStyle.baton
                    } else if let metadataRange = string.range(of: #"^([0-9]+\})"#, options: .regularExpression) {
                        string = "@" + String(string.suffix(from: metadataRange.upperBound))
                        lastElement.styles[index] = CharacterStyle.mention
                    }
                } else if string == "members" {
                    lastElement.metadata.append("members")
                    lastElement.styles[index] = CharacterStyle.mentionAll
                    string = "@!" + string
                } else if string == "project" {
                    lastElement.metadata.append("project")
                    lastElement.styles[index] = CharacterStyle.mentionAll
                    string = "@!" + string
                }
            }

			var token = Token(type: .string, inputString: string)
			token.metadataStrings.append(contentsOf: lastElement.metadata) 
			token.characterStyles = lastElement.styles
			string.removeAll()
			tokens.append(token)

            return
		}
		
		var accumulatedString = ""
		for element in elementArray {
            let isCode = element.styles.contains(where: { $0.isEqualTo(CharacterStyle.code) })
            if !isCode || element.character == "`" {
                guard element.type != .escape else {
                    continue
                }

                guard element.type == .string || element.type == .space || element.type == .newline else {
                    empty(&accumulatedString, into: &output)
                        continue
                }
                if lastElement.styles as? [CharacterStyle] != element.styles as? [CharacterStyle] {
                    empty(&accumulatedString, into: &output)
                }
            }

			accumulatedString.append(element.character)
			lastElement = element
		}
		empty(&accumulatedString, into: &output)
		
		self.currentPerfomanceLog.tag(with: "(finished all rules)")
		
		if enableLog {
			os_log("=====RULE PROCESSING COMPLETE=====", log: .tokenising, type: .info)
			os_log("==================================", log: .tokenising, type: .info)
		}
		return output
	}
}


extension String {
	func repeating( _ max : Int ) -> String {
		var output = self
		for _ in 1..<max {
			output += self
		}
		return output
	}
}
