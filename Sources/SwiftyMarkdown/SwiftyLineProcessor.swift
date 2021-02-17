//
//  SwiftyLineProcessor.swift
//  SwiftyMarkdown
//
//  Created by Anthony Keller on 09/15/2020.
//  Copyright © 2020 Voyage Travel Apps. All rights reserved.
//

import Foundation
import os.log

extension OSLog {
	private static var subsystem = "SwiftyLineProcessor"
	static let swiftyLineProcessorPerformance = OSLog(subsystem: subsystem, category: "Swifty Line Processor Performance")
}

public protocol LineStyling {
    var shouldTokeniseLine : Bool { get }
    func styleIfFoundStyleAffectsPreviousLine() -> LineStyling?
}

public struct SwiftyLine : CustomStringConvertible {
    public var line : String
    public var prefix : String = ""
    public var lineStyle : LineStyling
    public var indent : Int = 0
    public var space : Int = 0
    public var description: String {
        return self.line
    }
}

extension SwiftyLine : Equatable {
    public static func == ( _ lhs : SwiftyLine, _ rhs : SwiftyLine ) -> Bool {
        return lhs.line == rhs.line
    }
}

public enum Remove {
    case leading
    case trailing
    case both
    case entireLine
    case none
}

public enum ChangeApplication {
    case current
    case previous
	case untilClose
}

public struct FrontMatterRule {
	let openTag : String
	let closeTag : String
	let keyValueSeparator : Character
}

public struct LineRule {
    let token : String
    let otherTokens : [String]
    let removeFrom : Remove
    let type : LineStyling
    let shouldTrim : Bool
    let changeAppliesTo : ChangeApplication
    let useRegex: Bool
    let finder: ((String) -> Range<String.Index>?)?

    public init(token : String, otherTokens : [String] = [], type : LineStyling, removeFrom : Remove = .leading, shouldTrim : Bool = true, changeAppliesTo : ChangeApplication = .current, useRegex: Bool = false, finder: ((String) -> Range<String.Index>?)? = nil) {
        self.token = token
        self.otherTokens = otherTokens
        self.type = type
        self.removeFrom = removeFrom
        self.shouldTrim = shouldTrim
        self.changeAppliesTo = changeAppliesTo
        self.useRegex = useRegex
        self.finder = finder
    }
}

public class SwiftyLineProcessor {
    
	public var processEmptyStrings : LineStyling?
	public internal(set) var frontMatterAttributes : [String : String] = [:]
	
	var closeToken : String? = nil
    let defaultType : LineStyling
    
    let lineRules : [LineRule]
	let frontMatterRules : [FrontMatterRule]
	
	let perfomanceLog = PerformanceLog(with: "SwiftyLineProcessorPerformanceLogging", identifier: "Line Processor", log: OSLog.swiftyLineProcessorPerformance)
	    
	public init( rules : [LineRule], defaultRule: LineStyling, frontMatterRules : [FrontMatterRule] = []) {
        self.lineRules = rules
        self.defaultType = defaultRule
		self.frontMatterRules = frontMatterRules
    }
    
    func findLeadingLineElement( _ element : LineRule, in string : String , prevLine: SwiftyLine?) -> (String?, String?) {
        var output = string

        var tokens = [element.token]
        tokens.append(contentsOf: element.otherTokens)

        for token in tokens.filter({ $0.count > 0 }) {
            if element.useRegex {
                if let range = output.range(of: "^\(token)", options: .regularExpression) {
                    let prefix = String(output[range])
                    output.removeSubrange(range)
                    return (output, prefix)
                }
            } else if let range = output.index(output.startIndex, offsetBy: token.count, limitedBy: output.endIndex), output[output.startIndex..<range] == token {
                let prefix = String(output[range])
                output.removeSubrange(output.startIndex..<range)
                return (output, prefix)
            }
        }

        if let range = element.finder?(output) {
            let prefix = String(output[range])
            output.removeSubrange(range)
            return (output, prefix)
        }

        return (nil, nil)
    }
    
    func findTrailingLineElement( _ element : LineRule, in string : String ) -> String {
        var output = string

        if element.useRegex {
            if let range = output.range(of: "\(element.token)$", options: .regularExpression) {
                output.removeSubrange(range)
                return output
            }
        }

        let token = element.token.trimmingCharacters(in: .whitespaces)
        if let range = output.index(output.endIndex, offsetBy: -(token.count), limitedBy: output.startIndex), output[range..<output.endIndex] == token {
            output.removeSubrange(range..<output.endIndex)
            return output
            
        }
        return ""
    }

    func isList(_ lineStyle: MarkdownLineStyle) -> Bool {
        return lineStyle == .orderedList || lineStyle == .orderedListIndent || lineStyle == .unorderedList || lineStyle == .unorderedListIndent
    }

    func processLineLevelAttributes( _ text : String, prevLine: SwiftyLine?) -> SwiftyLine? {
        if text.isEmpty, let style = processEmptyStrings {
            return SwiftyLine(line: "", lineStyle: style)
        }

        let previousLines = lineRules.filter({ $0.changeAppliesTo == .previous })

        for element in lineRules {
            guard element.token.count > 0 || element.finder != nil else {
                continue
            }
            var output : String? = (element.shouldTrim) ? text.trimmingCharacters(in: .whitespaces) : text
            var prefix : String? = ""
            let unprocessed = output
			
			if let hasToken = self.closeToken, unprocessed != hasToken {
				return nil
			}

            switch element.removeFrom {
            case .leading:
                (output, prefix) = findLeadingLineElement(element, in: output!, prevLine: prevLine)
            /*case .trailing:
                output = findTrailingLineElement(element, in: output!)
            case .both:
                output = findLeadingLineElement(element, in: output!, prevStyle: prevStyle)
                output = findTrailingLineElement(element, in: output!)
			case .entireLine:
				let maybeOutput = output!.replacingOccurrences(of: element.token, with: "")
				output = ( maybeOutput.isEmpty ) ? maybeOutput : output*/
            default:
                break
            }

            guard var out = output else {
                continue
            }

            // Only if the output has changed in some way
            guard unprocessed != out else {
                continue
            }
			if element.changeAppliesTo == .untilClose {
				self.closeToken = (self.closeToken == nil) ? element.token : nil
				return nil
			}

            out = (element.shouldTrim) ? out.trimmingCharacters(in: .whitespaces) : out

            var line = SwiftyLine(line: out, lineStyle: element.type)
            line.prefix = prefix ?? ""
            switch element.type as! MarkdownLineStyle {
            case .orderedListIndent, .unorderedListIndent:
                var spaceCount = 0
                for c in line.prefix {
                    if c == " " {
                        spaceCount += 1
                    } else if c == "\t" {
                        spaceCount += 3
                    } else {
                        break
                    }
                }
                line.space = spaceCount
            default:
                if let s = prevLine?.lineStyle as? MarkdownLineStyle, isList(s) {
                    line.lineStyle = MarkdownLineStyle.body
                }
                break
            }

            return line
        }
        
		for element in previousLines {
			let output = (element.shouldTrim) ? text.trimmingCharacters(in: .whitespaces) : text
			let charSet = CharacterSet(charactersIn: element.token )
			if output.unicodeScalars.allSatisfy({ charSet.contains($0) }) {
				return SwiftyLine(line: "", lineStyle: element.type)
			}
		}
		
        return SwiftyLine(line: text.trimmingCharacters(in: .whitespaces), lineStyle: defaultType)
    }
	
	func processFrontMatter( _ strings : [String] ) -> [String] {
		guard let firstString = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) else {
			return strings
		}
		var rulesToApply : FrontMatterRule? = nil
		for matter in self.frontMatterRules {
			if firstString == matter.openTag {
				rulesToApply = matter
				break
			}
		}
		guard let existentRules = rulesToApply, strings.count > 1 else {
			return strings
		}
		var outputString = strings
		// Remove the first line, which is the front matter opening tag
		let _ = outputString.removeFirst()
		var closeFound = false
		while !closeFound {
			let nextString = outputString.removeFirst()
			if nextString == existentRules.closeTag {
				closeFound = true
				continue
			}
			var keyValue = nextString.components(separatedBy: "\(existentRules.keyValueSeparator)")
			if keyValue.count < 2 {
				continue
			}
			let key = keyValue.removeFirst()
			let value = keyValue.joined()
			self.frontMatterAttributes[key] = value
		}
		while outputString.first?.isEmpty ?? false {
			outputString.removeFirst()
		}
		return outputString
	}
    
    public func process( _ string : String ) -> [SwiftyLine] {
        var foundAttributes : [SwiftyLine] = []
		
		
		self.perfomanceLog.start()
		
		var lines = string.components(separatedBy: CharacterSet.newlines)
		lines = self.processFrontMatter(lines)
		
		self.perfomanceLog.tag(with: "(Front matter completed)")

        var prevStyle: SwiftyLine? = nil
        for heading in lines {
            
            if processEmptyStrings == nil && heading.isEmpty {
                continue
            }
			            
            guard let input = processLineLevelAttributes(String(heading), prevLine: prevStyle) else {
				continue
			}

            if input.line.count > 0 {
                if let p = prevStyle?.lineStyle as? MarkdownLineStyle, let i = input.lineStyle as? MarkdownLineStyle, isList(p), i == .body {
                    foundAttributes[foundAttributes.count - 1].line.append("\n" + input.line)
                    continue
                }
            }

            prevStyle = input
			
            /*if let existentPrevious = input.lineStyle.styleIfFoundStyleAffectsPreviousLine(), foundAttributes.count > 0 {
                if let idx = foundAttributes.firstIndex(of: foundAttributes.last!) {
                    let updatedPrevious = foundAttributes.last!
                    foundAttributes[idx] = SwiftyLine(line: updatedPrevious.line, lineStyle: existentPrevious)
                }
                continue
            }*/



            foundAttributes.append(input)
			
			self.perfomanceLog.tag(with: "(line completed: \(heading)")
        }

        for i in 1..<foundAttributes.count - 0 {
            switch foundAttributes[i].lineStyle as! MarkdownLineStyle {
            case .orderedList, .orderedListIndent, .unorderedList, .unorderedListIndent:

                for j in (0..<i).reversed() {
                    if let s = (foundAttributes[j].lineStyle as? MarkdownLineStyle), isList(s) {
                        let iSpace = foundAttributes[i].space
                        let jSpace = foundAttributes[j].space
                        if (jSpace + 2...jSpace + 3) ~= iSpace {
                            foundAttributes[i].indent = foundAttributes[j].indent + 1
                            break
                        } else if (jSpace...jSpace + 1) ~= iSpace {
                            foundAttributes[i].indent = foundAttributes[j].indent
                            break
                        }
                    } else if foundAttributes[j].lineStyle as? MarkdownLineStyle == .body {
                        break
                    }
                }

                break

            default:
                break
            }

        }

        return foundAttributes
    }
    
}
