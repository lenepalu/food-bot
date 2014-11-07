cheerio = require 'cheerio'
request = require 'request'
_ = require 'lodash'
Bacon = require 'baconjs'

baseUrl = 'https://ruoka.citymarket.fi'

fetchPage = (pageUrl, extractor, cb) ->
  requestOptions =
    url: baseUrl + pageUrl
    jar: true
  request.get(requestOptions, (err, response, body) ->
    if err
      cb(err)
    else
      cb(null, extractor(cheerio.load(body)))
  )

extractProductPaginationUrls = ($) ->
  $('.product-list-controls-top .pagination li a').map(() ->
    productPageUrl = $(this).attr('href')
  ).get()

extractProductCategories = ($) ->
  $('.product-category a').map(() ->
    categoryUrl = $(this).attr('href')
    data =
      id: /[0-9]+/.exec(categoryUrl)[0]
      url: categoryUrl
      name: $(this).find('.product-category-name span:first-child').text()
      img: $(this).find('.product-category-image img').attr('src')
  ).get()

fetchProductPaginationUrls = (url, cb) ->
  fetchPage(url, extractProductPaginationUrls, cb)

fetchProductSubCategories = (url, cb) ->
  fetchPage(url, extractProductCategories, cb)

fetchProductCategories = (cb) ->
  fetchPage('/pk-seutu/info/FrontPageView.action', extractProductCategories, cb)

productCategoriesStream = () ->
  Bacon.fromNodeCallback(fetchProductCategories).flatMap(Bacon.fromArray)

productSubCategoriesStream = (category) ->
  Bacon.combineTemplate
    id: category.id
    name: category.name
    img: category.img
    children: Bacon.fromNodeCallback(fetchProductSubCategories, category.url)

productPaginationUrlsStream = (categoryWithChildren) ->
  paginationUrlsStream = (category) -> Bacon.combineTemplate( {
      category: category
      urls: Bacon.fromNodeCallback(fetchProductPaginationUrls, category)
    }
  )

  Bacon.combineTemplate( {
    category: categoryWithChildren.category
    children: Bacon.fromArray(categoryWithChildren.children).flatMapConcat(paginationUrlsStream)
  })

productCategoriesStream()
.flatMapWithConcurrencyLimit(5, productSubCategoriesStream)
#.flatMapWithConcurrencyLimit(5, productPaginationUrlsStream)
.log()

