# Yex vs Y.js Feature Comparison

## Summary

The Elixir Yex implementation covers the core CRDT functionality but is missing several significant features from Y.js. Here's a comprehensive comparison:

---

## IMPLEMENTED IN YEX

### CRDT Types
- **Y.Array** - Ordered sequence with put, append, delete operations
- **Y.Map** - Key-value store with conflict resolution
- **Y.Text** - Collaborative text with rich text formatting support
- **Y.Unknown** - Placeholder for lazy type initialization

### Core Infrastructure
- **Y.Doc** - GenServer-based document container
- **Y.Transaction** - Atomic change batching and tracking
- **Y.Item** - Core data structure with origin-based ordering
- **Y.ID** - Client + clock identifiers
- **Y.DeleteSet** - Tombstone tracking

### Encoding/Decoding
- **V2 Protocol** - Compatible with Y.js binary format
- **State Vector** - Differential sync support
- **RLE Encoding** - Efficient compression via specialized buffers

### Data Structures
- **Finger Tree** - Efficient tree structure for Text and Array
- **Item Integration** - Conflict resolution algorithm
- **Y.Skip** - Gap placeholder for out-of-order struct integration
- **Y.GC** - Garbage collection markers

---

## POTENTIAL BUG: Skip Tracking for Origin Validation

### The Issue

Y.js tracks Skip ranges in `store.skips` and checks them during `getMissing()` (Item.js:400-407):

```javascript
if (this.origin && (this.origin.clock >= getState(store, this.origin.client)
    || store.skips.hasId(this.origin))) {
  return this.origin.client  // Dependency missing!
}
```

Yex only checks `origin.clock >= highest_clock` in `valid_origin?` (item.ex:310-314) — it **doesn't** check if the origin falls within a gap/skip range.

### Edge Case Scenario

1. Client A has items at clocks 0-9
2. Yex receives update with only clocks 5-9 (0-4 missing due to network)
3. Yex creates Skip for 0-4 but doesn't track it
4. Later, an item arrives with `origin` pointing to clock 2 (within the gap)
5. Yex says "clock 2 < highest_clock(10), valid!" — **but item at clock 2 doesn't exist!**

### How It Might Be Mitigated

Yex may handle this downstream:
- `Doc.find_item()` returns `nil` for missing items
- `find_left_for()` handles `nil` origins gracefully
- Failed integrations go to `pending_structs` for retry

But this is less efficient than Y.js's approach of catching it early in validation.

### Recommendation

Consider adding a `skips` IdSet to track gap ranges and check them in `valid_origin?`, `valid_right_origin?`, and `valid_parent?`.

---

## MISSING FROM YEX

### 1. XML Types (High Priority for Rich Text Editors)
| Y.js Feature | Description |
|--------------|-------------|
| `YXmlFragment` | List of XML elements/text nodes |
| `YXmlElement` | Element with attributes and children |
| `YXmlText` | Text content within XML elements |
| `YXmlHook` | Special map-like type for XML |

**Impact:** Required for ProseMirror, Slate, Quill, and other rich text editor bindings.

### 2. Undo/Redo Manager (High Priority)
| Y.js Feature | Description |
|--------------|-------------|
| `UndoManager` | Stack-based undo/redo |
| `captureTimeout` | Batch edits into single undo step |
| `trackedOrigins` | Track specific transaction origins |
| `deleteFilter` | Control what can be deleted during undo |
| `StackItem` events | `stack-item-added`, `stack-item-popped` |

**Impact:** Essential for any editor integration. Users expect Ctrl+Z/Ctrl+Y to work.

### 3. Snapshots (Medium Priority)
| Y.js Feature | Description |
|--------------|-------------|
| `snapshot(doc)` | Create point-in-time snapshot |
| `createDocFromSnapshot()` | Restore document to snapshot state |
| `encodeSnapshot()` / `decodeSnapshot()` | Snapshot serialization |
| `equalSnapshots()` | Compare snapshots |

**Impact:** Enables version history, time travel, and document diffing.

### 4. Relative Positions (Medium Priority)
| Y.js Feature | Description |
|--------------|-------------|
| `RelativePosition` | Stable position references surviving edits |
| `createRelativePositionFromIndex()` | Create from numeric position |
| `createAbsolutePositionFromRelativePosition()` | Convert back |
| Position with `assoc` | Association direction (-1 left, >=0 right) |

**Impact:** Required for cursor/selection synchronization in collaborative editors.

### 5. Awareness Protocol (Medium Priority)
| Y.js Feature | Description |
|--------------|-------------|
| `Awareness` class | Transient peer state (cursors, presence) |
| Local state management | Set/get local awareness state |
| Remote state tracking | Track other users' states |
| Timeout handling | Auto-remove stale awareness |

**Impact:** User presence indicators, cursor positions, "who's editing" features.

### 6. Event System / Observation (Medium Priority)
| Y.js Feature | Description |
|--------------|-------------|
| `observe(callback)` | Listen to type changes |
| `observeDeep(callback)` | Deep tree observation |
| `YEvent` | Change details (delta, keysChanged, etc.) |
| Transaction events | `beforeTransaction`, `afterTransaction` |

**Impact:** Yex has basic transaction support but lacks the rich event/observer pattern.

### 7. Content Types
| Y.js Feature | Yex Status |
|--------------|------------|
| `ContentString` | Implemented |
| `ContentBinary` | Implemented |
| `ContentJSON` | Implemented |
| `ContentFormat` | Implemented |
| `ContentDeleted` | Implemented |
| `ContentEmbed` | **Missing** - Rich media embedding |
| `ContentAny` | **Missing** - Arbitrary JS objects |
| `ContentDoc` | **Missing** - Subdocuments |

### 8. Subdocuments (Lower Priority)
| Y.js Feature | Description |
|--------------|-------------|
| Nested `Y.Doc` | Documents containing other documents |
| `subdocs` property | Track child documents |
| `loadSubdocument()` | Load child document |
| Lazy loading | Load subdocs on demand |

**Impact:** Enables large document composition and lazy loading.

### 9. Search Markers (Performance Optimization)
| Y.js Feature | Description |
|--------------|-------------|
| Search marker cache | Cache up to 80 most-used positions |
| Auto-refresh | Markers updated as document changes |

**Impact:** Y.js uses this for O(1) position lookup in large texts. Yex uses Finger Tree which has O(log n) access, so less critical.

### 10. V1 Encoding Support
| Y.js Feature | Description |
|--------------|-------------|
| V1 Encoder/Decoder | Simpler but larger encoding |
| Format conversion | `convertUpdateFormatV1ToV2()` |

**Impact:** Yex only supports V2. V1 compatibility might be needed for older Y.js clients.

### 11. Update Utilities
| Y.js Feature | Yex Status |
|--------------|------------|
| `encodeStateAsUpdate()` | Implemented |
| `applyUpdate()` | Implemented |
| `encodeStateVector()` | Implemented |
| `mergeUpdates()` | Internal only (dummy impl) - Not planned for public API |
| `diffUpdate()` | Internal only - Not planned for public API |

**Note:** `mergeUpdates` and `diffUpdate` in Y.js are primarily used for:
- Storage compaction (merging incremental updates)
- Sync without loading Y.Doc (working on binary blobs directly)

Yex uses these internally but doesn't need full implementations since it works with loaded documents.

### 12. Abstract Connector / Provider Interface
| Y.js Feature | Description |
|--------------|-------------|
| `AbstractConnector` | Base class for network providers |
| Provider pattern | Pluggable transport layer |

**Impact:** Y.js has y-websocket, y-webrtc, y-indexeddb. Yex would need similar abstractions.

---

## FEATURE PRIORITY MATRIX

| Feature | Priority | Effort | Reason |
|---------|----------|--------|--------|
| Undo/Redo Manager | High | Medium | Essential for any editor |
| XML Types | High | High | Required for rich text editors |
| Relative Positions | High | Low | Cursor sync |
| Event/Observer System | Medium | Medium | Reactive UI updates |
| Awareness Protocol | Medium | Low | User presence |
| Snapshots | Medium | Medium | Version history |
| ContentEmbed | Medium | Low | Rich media |
| Subdocuments | Low | Medium | Document composition |
| mergeUpdates/diffUpdate | Low | Low | Not needed - internal only |
| V1 Encoding | Low | Medium | Legacy compatibility |

---

## IMPLEMENTATION NOTES

### What Yex Does Well
1. **Finger Tree structure** - Efficient O(log n) operations vs Y.js linked list with search markers
2. **GenServer-based Doc** - Fits Elixir/OTP patterns well
3. **V2 Protocol compatibility** - Can sync with Y.js clients
4. **Property-tested** - Extensive CRDT property tests (115KB test file)

### Architecture Differences
1. Y.js uses mutable linked lists; Yex uses immutable Finger Trees
2. Y.js is event-driven; Yex is more functional/transactional
3. Y.js has tight editor bindings; Yex is more standalone

---

## RECOMMENDED NEXT STEPS

1. **Phase 1: Core Editor Support**
   - Implement UndoManager
   - Add RelativePosition support
   - Add proper event/observer system

2. **Phase 2: Rich Text**
   - Implement YXmlFragment, YXmlElement, YXmlText
   - Add ContentEmbed support

3. **Phase 3: Collaboration Features**
   - Implement Awareness protocol
   - Add Snapshot support

4. **Phase 4: Advanced**
   - Subdocument support
   - Provider/Connector abstractions

---

## KNOWN ISSUES / TECHNICAL DEBT

### 1. Skip Tracking (Potential Bug)
- **Location:** `lib/y/item.ex:310-314` (`valid_origin?`, `valid_right_origin?`, `valid_parent?`)
- **Issue:** Missing check for origins falling within gap/skip ranges
- **Risk:** Less efficient integration when structs arrive out of order
- **Fix:** Add `skips` IdSet tracking to Doc, check in validation functions

### 2. Dummy `merge_updates` Implementation
- **Location:** `lib/y/encoder.ex:198-203`
- **Issue:** Returns only first update, drops pending data
- **Risk:** Lost pending structs/delete sets when encoding with pending data
- **Decision:** Not fixing - internal use only, rare edge case

---

*Last updated: January 2026*
