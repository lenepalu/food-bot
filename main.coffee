https = require 'https'
https.globalAgent.maxSockets = 20;
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

cleanedText = ($element) ->
  $element.text().replace('\\r','').replace('\\n','').replace(/^\s+|\s+$/g, '');

extractProduct = ($) ->
  $('.product-page-wrapper').map(() ->
    data =
      id: Number($(this).find('.product-purchase form').attr('data-product-id'))
      name: $(this).find('.product-name h1').text()
      price: $(this).find('.product-price .price-int').text() + "." + $(this).find('.product-price .price-fraction').text() + $(this).find('.product-price .currency').text()
      unit: $(this).find('.product-price .selling-unit').text()
      unitPrice: $(this).find('.product-unit-price').text()
      ean: /[0-9]+/.exec($(this).find('.product-details .ean').text())[0]
      shortDescription: cleanedText($(this).find('.short-description'))
      img: $(this).find('#productImageLink').attr('href') #.replace('//', '/')
      contents: $(this).find('.additional-product-info .contents').html()
  ).get()

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

productCategoriesStream().flatMapConcat(productSubCategoriesStream).map((category) -> JSON.stringify(category, undefined, 2)).log()