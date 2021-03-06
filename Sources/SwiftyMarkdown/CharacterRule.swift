//
//  CharacterRule.swift
//  SwiftyMarkdown
//
//  Created by Anthony Keller on 09/15/2020.
//

import Foundation

public enum SpaceAllowed {
	case no
	case bothSides
	case oneSide
	case leadingSide
	case trailingSide
}

public enum Cancel {
	case none
	case allRemaining
	case currentSet
}

public enum CharacterRuleTagType {
    case none
	case open
	case close
	case metadataOpen
	case metadataClose
	case repeating
}


public struct CharacterRuleTag: Equatable {
	let tag : String
	let type : CharacterRuleTagType
	
	public init( tag : String, type : CharacterRuleTagType ) {
		self.tag = tag
		self.type = type
	}

    public static func == (lhs: CharacterRuleTag, rhs: CharacterRuleTag) -> Bool {
        return lhs.tag == rhs.tag &&
            lhs.type == rhs.type
    }
}

public struct CharacterRule : CustomStringConvertible, Equatable {
	
	public let primaryTag : CharacterRuleTag
	public let tags : [CharacterRuleTag]
	public let escapeCharacters : [Character]
	public let styles : [Int : CharacterStyling]
	public let minTags : Int
	public let maxTags : Int
	public var metadataLookup : Bool = false
	public var isRepeatingTag : Bool {
		return self.primaryTag.type == .repeating
	}
	public var definesBoundary = false
	public var shouldCancelRemainingRules = false
	public var balancedTags = false
    public var requiredSpace = false

    public static func == (lhs: CharacterRule, rhs: CharacterRule) -> Bool {
        return lhs.primaryTag == rhs.primaryTag &&
            lhs.tags == rhs.tags &&
            lhs.escapeCharacters == rhs.escapeCharacters &&
            lhs.minTags == rhs.minTags &&
            lhs.maxTags == rhs.maxTags &&
            lhs.metadataLookup == rhs.metadataLookup &&
            lhs.definesBoundary == rhs.definesBoundary &&
            lhs.shouldCancelRemainingRules == rhs.shouldCancelRemainingRules &&
            lhs.balancedTags == rhs.balancedTags &&
            lhs.requiredSpace == rhs.requiredSpace
    }

	public var description: String {
		return "Character Rule with Open tag: \(self.primaryTag.tag) and current styles : \(self.styles) "
	}

	public func tag( for type : CharacterRuleTagType ) -> CharacterRuleTag? {
		return self.tags.filter({ $0.type == type }).first ?? nil
	}

	public init(primaryTag: CharacterRuleTag, otherTags: [CharacterRuleTag], escapeCharacters : [Character] = ["\\"], styles: [Int : CharacterStyling] = [:], minTags : Int = 1, maxTags : Int = 1, metadataLookup : Bool = false, definesBoundary : Bool = false, shouldCancelRemainingRules : Bool = false, balancedTags : Bool = false, requiredSpace : Bool = false) {
		self.primaryTag = primaryTag
		self.tags = otherTags
		self.escapeCharacters = escapeCharacters
		self.styles = styles
		self.metadataLookup = metadataLookup
		self.definesBoundary = definesBoundary
		self.shouldCancelRemainingRules = shouldCancelRemainingRules
		self.minTags = maxTags < minTags ? maxTags : minTags
		self.maxTags = minTags > maxTags ? minTags : maxTags
		self.balancedTags = balancedTags
        self.requiredSpace = requiredSpace
	}
}



enum ElementType {
	case tag
	case escape
	case string
	case space
	case newline
	case metadata
}

struct Element {
	let character : Character
	var type : ElementType
	var boundaryCount : Int = 0
	var isComplete : Bool = false
	var styles : [CharacterStyling] = []
	var metadata : [String] = []
    var characterRuleTagType : CharacterRuleTagType = .none
}

extension CharacterSet {
    func containsUnicodeScalars(of character: Character) -> Bool {
        return character.unicodeScalars.allSatisfy(contains(_:))
    }
}
