import AppKit

extension NSView {
    var nearestTableView: NSTableView? {
        var view: NSView? = self
        while let current = view {
            if let found = current.findTableView() { return found }
            view = current.superview
        }
        return nil
    }

    var nearestCollectionView: NSCollectionView? {
        var view: NSView? = self
        while let current = view {
            if let found = current.findCollectionView() { return found }
            view = current.superview
        }
        return nil
    }

    func findTableView() -> NSTableView? {
        if let tableView = self as? NSTableView { return tableView }
        if let scrollView = self as? NSScrollView,
           let tableView = scrollView.documentView as? NSTableView { return tableView }
        for subview in subviews {
            if let found = subview.findTableView() { return found }
        }
        return nil
    }

    func findCollectionView() -> NSCollectionView? {
        if let collectionView = self as? NSCollectionView { return collectionView }
        if let scrollView = self as? NSScrollView,
           let collectionView = scrollView.documentView as? NSCollectionView { return collectionView }
        for subview in subviews {
            if let found = subview.findCollectionView() { return found }
        }
        return nil
    }

    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let found = subview as? T { return found }
            if let found = subview.firstDescendant(ofType: type) { return found }
        }
        return nil
    }

    func superview<T: NSView>(ofType type: T.Type) -> T? {
        var view = self.superview
        while let current = view {
            if let found = current as? T { return found }
            view = current.superview
        }
        return nil
    }
}
