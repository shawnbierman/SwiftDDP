// Copyright (c) 2015 Peter Siegesmund <peter.siegesmund@icloud.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import RealmSwift

public class Datastore {
    public static let realm = try? Realm()
}

public class RealmCollection<T:RealmDocument>: Collection<T> {
    
    let realm = Datastore.realm
    
    public override init(name:String) {
        super.init(name: name)
    }
    
    public func count() -> Int {
        return self.find()!.count
    }
    
    public func flush() {
        // let realm = Datastore.realm
         realm?.write {
            realm?.deleteAll()
        }
    }
    
    // Document must have an id
    public func insert(json:NSDictionary) -> T {
        let doc = T()
        if let id = json["_id"] as? String { doc._id = id } else { doc._id = self.client.getId() }
        doc.apply(json)
        doc.insert()
        
        // Try adding the document on the server, but remove it if 
        // the insert is unsuccessful
        self.client.insert(name, doc: NSArray(arrayLiteral: json)) { result, error in
            if (error != nil) {
                doc.remove()
            }
        }
        return doc
    }
    
    public func insert(document:T) -> T {
        let json = document.jsonValue()
        return insert(json)
    }
    
    public func remove(id:String) {
        if let document = self.findOne(id){
            document.remove()
            self.client.remove(name, doc: NSArray(arrayLiteral: ["_id":id])) { result, error in
                if (error != nil) {
                    print("Error removing document \(document). Error: \(error)")
                    document.insert()
                }
            }
        }
    }
    
    public func remove(doc:T) {
        remove(doc._id)
    }
    
    public func update(doc:T) {
        let docCopy = doc.copy()
        doc.update()
        let dictionary = doc.jsonValue()
        self.client.update(name, doc: NSArray(arrayLiteral: dictionary)) { result, error in
            if (error != nil) {
                print("Error updating document \(doc). Error: \(error)")
                docCopy.update()
            }
        }
    }
    
    // Untrusted code can only be updated via id
    // format is {"_id":id},{"$set":{fields...}}
    public func update(id:String, fields:NSDictionary) {
        self.realm?.write {
            self.realm?.create(T, value: fields, update: true)
        }
        self.client.update(self.name, doc: [["_id":id], ["$set":fields]]) { result, error in
            if (error != nil) {
                print("Error updating document. Error: \(error)")
            } else {
                print("Result: \(result)")
            }
        }
    }
    
    public func find() -> Results<T>? {
        return self.realm?.objects(T.self)
    }
    
    public func find(_id:String) -> Results<T>? {
        return self.realm?.objects(T.self).filter(NSPredicate(format:"_id = '\(_id)'"))
    }
    
    public func find(query:NSPredicate) -> Results<T>? {
        return realm?.objects(T.self).filter(query)
    }
    
    public func findOne(_id:String) -> T? {
        let result = find(_id)
        if (result?.count > 0) {
            return result?[0]
        }
        return nil
    }
    
    public func findOne(query:NSPredicate) -> T? {
        let result = find(query)
        if (result?.count > 0) {
            return result?[0]
        }
        return nil
    }
    
    // Document was added from the server
    public override func documentWasAdded(collection:String, id:String, fields:NSDictionary?) {
        
        // Check that the document isn't already in the local collection
        guard let document = findOne(id) else {
            let document = T()
            document._id = id
            if let properties = fields { document.apply(properties) }
            document.insert()
            return
        }
        
        // Overwrite the local fields. This behavior should be revisited!
        if let properties = fields {
            realm?.write {
                document.apply(properties)
            }
        }
    }
    
    // Document was changed on the server
    public override func documentWasChanged(collection:String, id:String, fields:NSDictionary?, cleared:[String]?) {
        if let document = findOne(id),
           let properties = fields {
                realm?.write {
                    document.apply(properties)
                    if let deletedProperties = cleared {
                        for deletedProperty in deletedProperties {
                            document[deletedProperty] = ""
                        }
                    }
                }
            }
        }
    
    // Document was removed from subscription
    public override func documentWasRemoved(collection:String, id:String) {
        if let doc = findOne(id) {
            doc.remove()
        }
    }
}

// The field _id functions as the primary key and guarantees uniqueness
// _id property is immutable
public class RealmDocument: Object {
    
    public dynamic var _id = ""
    
    // Has this document been saved
    public var exists:Bool {
        return self.invalidated
    }
    
    public var r:Realm? {
        if (self.realm != nil) {
            return self.realm!
        }
        return Datastore.realm
    }
    
    public var persisted:Bool {
        if (self.realm != nil) {
            return true
        }
        return false
    }
    
    override public static func primaryKey() -> String {
        return "_id"
    }
    
    func propertyNames() -> [String] {
        return Mirror(reflecting: self).children.filter { $0.label != nil }.map { $0.label! }
    }
    
    public func insert() {
        r?.write {
            self.r?.add(self)
        }
    }
    
    public func update() {
        r?.write {
            self.r?.add(self, update:true)
        }
    }
    
    public func remove() {
        r?.write {
            self.r?.delete(self)
        }
    }
    
    // Simple one-level object to json translation; override for more
    // complex scenarios
    public func jsonValue() -> NSDictionary {
        
        let dictionary = NSMutableDictionary()
        
        for key in propertyNames() {
            let value = self.valueForKey(key)
            dictionary[key] = value
        }
        return dictionary as NSDictionary
    }
    
    public func apply(json:NSDictionary) {}
}
