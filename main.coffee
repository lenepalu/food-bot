cheerio = require 'cheerio'
request = require 'request'
_ = require 'lodash'
Bacon = require 'baconjs'

baseUrl = 'https://ruoka.citymarket.fi'

concat = (array, value) ->
  array.concat(value)

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

extractProductUrls = ($) ->
  $('.product-item .product_link').map(() ->
    $(this).attr("href")
  ).get()

extractProductCount = ($) ->
  Number(/[0-9]+/.exec($('.product-list-count').text())[0])

extractProductCategories = ($) ->
  $('.product-category a').map(() ->
    categoryUrl = $(this).attr('href')
    data =
      id: /[0-9]+/.exec(categoryUrl)[0]
      url: categoryUrl
      name: $(this).find('.product-category-name span:first-child').text()
      img: $(this).find('.product-category-image img').attr('src')
  ).get()

fetchProductUrls = (url, cb) ->
  fetchPage(url, extractProductUrls, cb)

fetchProductCount = (url, cb) ->
  fetchPage(url, extractProductCount, cb)

fetchProductSubCategories = (url, cb) ->
  fetchPage(url, extractProductCategories, cb)

fetchProductCategories = (cb) ->
  fetchPage('/pk-seutu/info/FrontPageView.action', extractProductCategories, cb)

productPaginationUrlsStream = (category) ->
  paginationUrlsStream = (productCount) ->
    maxIndex = if productCount < 24 then 1 else productCount / 24
    pageUrls = []
    for pageIndex in [1..maxIndex] by 1
      pageUrls.push(category.url + '?page.currentPage=' + pageIndex)
    Bacon.fromArray(pageUrls)

  productUrlsStream = (url) ->
    Bacon.fromNodeCallback(fetchProductUrls, url)

  Bacon.combineTemplate
    id: category.id
    name: category.name
    img: category.img
    productUrls: Bacon.fromNodeCallback(fetchProductCount, category.url).flatMap(paginationUrlsStream).flatMap(productUrlsStream).fold([], concat)

productSubCategoriesStream = (category) ->
  Bacon.combineTemplate
    id: category.id
    name: category.name
    img: category.img
    categories: Bacon.fromNodeCallback(fetchProductSubCategories, category.url).flatMap(Bacon.fromArray).flatMap(productPaginationUrlsStream).fold([], concat)

productCategoriesStream = () ->
  Bacon.fromNodeCallback(fetchProductCategories).flatMap(Bacon.fromArray)

productCategoriesStream().flatMapWithConcurrencyLimit(5, productSubCategoriesStream).map((category) -> JSON.stringify(category, undefined, 2)).log()