https = require 'https'
https.globalAgent.maxSockets = 100;
request = require 'request'
cheerio = require 'cheerio'
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

cleaned = (text) ->
  text.replace('\r', '').replace('\n', '').replace(/^\s+|\s+$/g, '');

extractProduct = ($) ->
  $('.product-page-container').map(() ->
    data =
      id: Number($(this).find('.product-purchase form').attr('data-product-id'))
      name: cleaned($(this).find('.product-name h2').text())
      price: $(this).find('.product-price .price-int').text() + "." + $(this).find('.product-price .price-fraction').text() + $(this).find('.product-price .currency').text()
      unit: $(this).find('.product-price .selling-unit').text()
      unitPrice: cleaned($(this).find('.product-unit-price').text()).replace('(', '').replace(')', '')
      ean: /[0-9]+/.exec($(this).find('.product-details th:contains(EAN-koodi)').next('td').text())[0]
      shortDescription: cleaned($(this).find('.short-description').text())
      img: $(this).find('#productImageLink').attr('href')
      contents: cleaned($(this).find('.product-details th:contains(\n                            Ainesosat)').next('td').text())
  )
  .get()

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
      id: Number(/[0-9]+/.exec(categoryUrl)[0])
      url: categoryUrl
      name: $(this).find('.product-category-name span:first-child').text()
      img: $(this).find('.product-category-image img').attr('src')
  ).get()

fetchProduct = (url, cb) -> fetchPage(url, extractProduct, cb)
fetchProductUrls = (url, cb) -> fetchPage(url, extractProductUrls, cb)
fetchProductCount = (url, cb) -> fetchPage(url, extractProductCount, cb)
fetchProductSubCategories = (url, cb) -> fetchPage(url, extractProductCategories, cb)
fetchProductCategories = (cb) -> fetchPage('/pk-seutu/info/FrontPageView.action', extractProductCategories, cb)

productPaginationUrlsStream = (category) ->
  paginationUrlsStream = (productCount) ->
    maxIndex = if productCount < 24 then 1 else productCount / 24
    pageUrls = []
    for pageIndex in [1..maxIndex] by 1
      pageUrls.push(category.url + '?page.currentPage=' + pageIndex)
    Bacon.fromArray(pageUrls)

  productUrlsStream = (url) -> Bacon.fromNodeCallback(fetchProductUrls, url)
  productsStream = (url) -> Bacon.fromNodeCallback(fetchProduct, url)

  Bacon.combineTemplate
    id: category.id
    name: category.name
    img: category.img
    products: Bacon.fromNodeCallback(fetchProductCount, category.url)
      .flatMapConcat(paginationUrlsStream)
      .flatMapConcat(productUrlsStream)
      .fold([], concat)
      .flatMap(Bacon.fromArray)
      .flatMapConcat(productsStream)
      .fold([], concat)

productSubCategoriesStream = (category) ->
  Bacon.combineTemplate
    id: category.id
    name: category.name
    img: category.img
    categories: Bacon.fromNodeCallback(fetchProductSubCategories, category.url).flatMap(Bacon.fromArray).flatMap(productPaginationUrlsStream).fold([], concat)

productCategoriesStream = () ->
  Bacon.fromNodeCallback(fetchProductCategories).flatMap(Bacon.fromArray)

productCategoriesStream().flatMapWithConcurrencyLimit(2, productSubCategoriesStream).map((category) -> JSON.stringify(category, undefined, 2)).log()