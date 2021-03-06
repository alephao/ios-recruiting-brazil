public struct Filter<T> {
  private let predicate: (T) -> Bool

  public init(predicate: @escaping (T) -> Bool) {
    self.predicate = predicate
  }

  public func runFilter(_ ts: [T]) -> [T] {
    ts.filter(predicate)
  }

  public func contramap<U>(_ f: @escaping (U) -> T) -> Filter<U> {
    Filter<U> { u in
      self.predicate(f(u))
    }
  }

  public func merge(with other: Filter<T>, strategy: Filters.Strategy) -> Filter<T> {
    switch strategy {
    case .and:
      return Filter<T> { t in
        self.predicate(t) && other.predicate(t)
      }
    case .or:
      return Filter<T> { t in
        self.predicate(t) || other.predicate(t)
      }
    }
  }
}

public enum Filters {
  public enum Strategy {
    case and
    case or
  }

  public static func movieFilter(byTitle titleSearchString: String) -> Filter<Movie> {
    let strippedString = titleSearchString.trimmingCharacters(in: .whitespaces)
    let searchItems = strippedString.components(separatedBy: " ") as [String]
    let predicates = searchItems.map(comparisonPredicateForTitle)
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    return Filter<Movie> { movie in
      predicate.evaluate(with: movie.title)
    }
  }

  public static func movieFilter(byYear year: String) -> Filter<Movie> {
    Filter<Movie> { movie in
      movie.year == year
    }
  }

  public static func movieFilter(byGenreIds genreIds: [Int16]) -> Filter<Movie> {
    Filter<Movie> { movie in
      Set(genreIds)
        .intersection(Set(movie.genreIds))
        .count > 0
    }
  }
}

private func comparisonPredicateForTitle(_ searchString: String) -> NSComparisonPredicate {
  let titleExpression = NSExpression(
    block: { value, _, _ in
      value!
    },
    arguments: nil
  )
  let searchStringExpression = NSExpression(forConstantValue: searchString)

  let titleSearchComparisonPredicate = NSComparisonPredicate(
    leftExpression: titleExpression,
    rightExpression: searchStringExpression,
    modifier: .direct,
    type: .contains,
    options: [.caseInsensitive, .diacriticInsensitive]
  )

  return titleSearchComparisonPredicate
}
