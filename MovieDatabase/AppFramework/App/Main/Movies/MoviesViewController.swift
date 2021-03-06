import Combine
import UIKit

public final class MoviesViewController: UICollectionViewController {
  // MARK: Types

  typealias DataSource = UICollectionViewDiffableDataSource<MoviesSection, MovieViewModel>
  typealias Snapshot = NSDiffableDataSourceSnapshot<MoviesSection, MovieViewModel>

  // MARK: UI

  private let refreshControl = UIRefreshControl()
  private lazy var resultsController = MoviesSearchResultsViewController(collectionViewLayout: Self.makeCollectionViewLayout())
  private lazy var searchController: UISearchController = {
    let searchController = UISearchController(searchResultsController: resultsController)
    searchController.searchBar.autocapitalizationType = .none
    searchController.searchResultsUpdater = self
    searchController.delegate = self
    return searchController
  }()

  private lazy var errorBackground: UIView = {
    let label = UILabel()
    label.textAlignment = .center
    label.text = L10n.Screen.Movies.errorMessage
    return label
  }()

  // MARK: Publishers

  private let _presentMovieDetails = PassthroughSubject<Movie, Never>()
  public lazy var presentMovieDetails: AnyPublisher<Movie, Never> = _presentMovieDetails.eraseToAnyPublisher()
  private let _refreshCells = PassthroughSubject<Void, Never>()
  private let _refresh = PassthroughSubject<Void, Never>()
  private let _nextPage = PassthroughSubject<Int, Never>()
  fileprivate let _searhText = CurrentValueSubject<String?, Never>(nil)

  // MARK: DataSource

  private lazy var dataSource: DataSource = {
    DataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, movieViewModel -> UICollectionViewCell? in
      guard let self = self else { return nil }
      let cell: MovieCell = collectionView.dequeue(for: indexPath)
      cell.setup(viewModel: movieViewModel, refresh: self._refreshCells.eraseToAnyPublisher())
      return cell
    }
  }()

  // MARK: Other Properties

  private var cancellables = Set<AnyCancellable>()
  private let viewModel: MoviesViewModel

  static func makeCollectionViewLayout() -> UICollectionViewCompositionalLayout {
    let itemSize = NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(0.48),
      heightDimension: .fractionalHeight(1.0)
    )

    let item = NSCollectionLayoutItem(layoutSize: itemSize)

    let groupSize = NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1),
      heightDimension: .absolute(230)
    )

    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: groupSize,
      subitems: [item]
    )
    group.interItemSpacing = NSCollectionLayoutSpacing.flexible(8)
    group.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: nil, top: nil, trailing: nil, bottom: .fixed(20))

    let section = NSCollectionLayoutSection(group: group)
    section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)

    let layout = UICollectionViewCompositionalLayout(section: section)

    return layout
  }

  // MARK: Lifecycle

  public init(viewModel: MoviesViewModel) {
    self.viewModel = viewModel
    let layout = Self.makeCollectionViewLayout()
    super.init(collectionViewLayout: layout)
    tabBarItem = UITabBarItem(
      title: L10n.Screen.Movies.title,
      image: UIImage(systemName: "list.bullet"), selectedImage: nil
    )
    title = L10n.Screen.Movies.title
    definesPresentationContext = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override public func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
    setupBindings()
  }

  override public func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    _refreshCells.send(())
  }

  var viewAlredyAppeared = false
  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !viewAlredyAppeared {
      _refresh.send(())
    }
    viewAlredyAppeared = true
  }

  // MARK: Methods

  private func setupUI() {
    navigationItem.searchController = searchController
    collectionView.backgroundColor = .systemBackground
    collectionView.register(MovieCell.self)
    collectionView.refreshControl = refreshControl
  }

  private func setupBindings() {
    refreshControl.addTarget(self, action: #selector(refresh), for: .primaryActionTriggered)

    let output = viewModel.transform(
      .init(
        refresh: _refresh
          .throttle(for: .milliseconds(1500), scheduler: DispatchQueue.main, latest: true)
          .eraseToAnyPublisher(),
        nextPage: _nextPage
          .removeDuplicates()
          .map { _ in () }
          .throttle(for: .milliseconds(1500), scheduler: DispatchQueue.main, latest: true)
          .eraseToAnyPublisher(),
        searchText: _searhText.eraseToAnyPublisher()
      )
    )

    output.values
      .receive(on: DispatchQueue.main)
      .sink(receiveValue: { [weak self] movies in
        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(movies)
        self?.dataSource.apply(snapshot)
      })
      .store(in: &cancellables)

    output.error
      .receive(on: DispatchQueue.main)
      .sink(receiveValue: { [weak self] _ in
        let alert = UIAlertController(title: L10n.Global.Title.error, message: L10n.Screen.Movies.errorMessage, preferredStyle: .alert)
        let action = UIAlertAction(title: L10n.Global.Action.ok, style: .default, handler: nil)
        alert.addAction(action)
        self?.present(alert, animated: true, completion: nil)
      })
      .store(in: &cancellables)

    output.isRefreshing
      .filter { !$0 }
      .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
      .receive(on: DispatchQueue.main)
      .sink(receiveValue: { [weak self] _ in
        self?.refreshControl.endRefreshing()
      })
      .store(in: &cancellables)

    output.filteredValues
      .receive(on: DispatchQueue.main)
      .sink(receiveValue: { [weak self] movies in
        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(movies)
        self?.resultsController.dataSource.apply(snapshot)
      })
      .store(in: &cancellables)

    Publishers.Merge(
      output.values.map { $0.count == 0 },
      output.error.map { _ in true }
    )
    .removeDuplicates()
    .receive(on: DispatchQueue.main)
    .sink(receiveValue: { [weak self] empty in
      if empty {
        self?.collectionView.backgroundView = self?.errorBackground
      } else {
        self?.collectionView.backgroundView = nil
      }
    })
    .store(in: &cancellables)

    output.filteredValues
      .map { values in values.count == 0 }
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink(receiveValue: { [weak self] empty in
        if empty {
          self?.resultsController.setEmptyResultsBackground()
        } else {
          self?.resultsController.removeEmptyResultsBackground()
        }
      })
      .store(in: &cancellables)

    resultsController.didSelectItem
      .map(\.movie)
      .subscribe(_presentMovieDetails)
      .store(in: &cancellables)
  }

  @objc private func refresh() {
    guard refreshControl.isRefreshing else { return }
    _refresh.send(())
  }

  // MARK: UICollectionViewDelegate

  override public func collectionView(_ collectionView: UICollectionView, willDisplay _: UICollectionViewCell, forItemAt indexPath: IndexPath) {
    let numberOfItems = collectionView.numberOfItems(inSection: 0)
    if indexPath.item == numberOfItems - 1 {
      _nextPage.send(numberOfItems)
    }
  }

  override public func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
    _presentMovieDetails.send(item.movie)
  }
}

// MARK: UISearchResultsUpdating

extension MoviesViewController: UISearchResultsUpdating {
  public func updateSearchResults(for searchController: UISearchController) {
    _searhText.send(searchController.searchBar.text)
  }
}

// MARK: UISearchControllerDelegate

extension MoviesViewController: UISearchControllerDelegate {
  public func didDismissSearchController(_: UISearchController) {
    _refreshCells.send(())
  }
}
