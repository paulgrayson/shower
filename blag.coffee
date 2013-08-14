Posts = new Meteor.Collection("posts")

# Demo posts
POSTS = [
  {
    url: "this-is-post-1",
    name: "Post 1",
    body: "This is the body of post 1. This is not a summary",
    visible: true,
    created_at: new Date()
  },
  {
    url: "and-post-2",
    name: "Welcome to Post 2",
    body: "Post 2 is much more interesting than post 1",
    visible: true,
    created_at: new Date()
  }
]


RouteHelper = {
  calcRoute: ->
    path = window.location.href.split('/')[3..-1]
    if path[0] == ''
      {action: 'index', params: {}}
    else if path[0] == 'admin'
      {action: 'admin', params: {}}
    else if path[0] == 'create'
      {action: 'create', params: {}}
    else if path[0] == 'edit'
      {action: 'edit', params: {path: _.rest(path)}}
    else
      {action: 'show', params: {path: path}}

  ensureForwardSlashPrefix: (url)->
    return if url[0] != '/' then "/#{url}" else url

  removeForwardSlashPrefix: (url)->
    return url.replace(/^\//, '')

  render404: ->
    # TODO how do we do this?!?!
}

PostsHelper = {
  all: ->
    return Posts.find({}, {sort: {created_at: 1, name: 1}})

  visible: ->
    return Posts.find({visible: true}, {created_at: 1, name: 1})

  thisPost: (that)->
    return Posts.findOne(that._id)

  isNewUrl: (url)->
    Posts.find({url: url}).count() == 0

  summary: (body)->
    words = body.split(" ")
    if words.length >= 60 
      _.first(words,60).join(' ') + "..."
    else
      body

  findByUrl: (url)->
    return Posts.findOne({url: url})

  validateBase: (post)->
    errors = {}
    errors['name'] = "Please enter a name for the post" if post.name == ''
    errors['url'] = "Please enter a url for the post" if post.url == ''
    errors['body'] = "Please enter a body for the post" if post.body == ''
    validation = {
      errors: errors
      ok: -> 
        return _.values(this.errors).length == 0
    }
    return validation

  validateCreate: (post)->
    validation = this.validateBase(post)
    validation.errors['url'] = "Sorry but this url is already in use. Please change the url" if post.url != '' and !this.isNewUrl(post.url)
    return validation

  validateUpdate: (post)->
    validation = this.validateBase(post)
    # TODO prevent change of url to one already in use by another post
    return validation

  isValid: (post)->
    return this.validateBase(post).ok()
}


# CLIENT
if Meteor.isClient

  Session.set("route", RouteHelper.calcRoute())

  goto = (url)->
    window.history.pushState({}, '', RouteHelper.ensureForwardSlashPrefix(url))
    Session.set("route", RouteHelper.calcRoute())
    return false    # don't reload

  # make sure page reflects url after back button pressed
  window.onpopstate = ->
    Session.set("route", RouteHelper.calcRoute())

  route = -> Session.get('route')

  pageName = ->
    return window.location.href.split('/')[3..-1]

  isAdminUser = ->
    # TODO proper admin not hardwired
    return Meteor.user()?.services?.twitter?.screenName == "pheater"


# HEADER
  # TODO get this from a config file OR have a setup screen then store in mongo
  Template.header.blogName = "Bananas are not the only fruit"

  Template.header.events({
    'click .logo': -> goto('/')
  })


# FOOTER
  Template.footer.admin = ->
    return isAdminUser()

  Template.footer.events({
    'click .admin-link': -> goto('/admin')
  })


# INDEX
  Template.index.isCurrentPage = ->
    return route().action == 'index'

  Template.index.posts = ->
     return PostsHelper.visible()

  Template.index.events({
    'click .post-link': -> goto(this.url)
  })

  Template.postSummary.summary = ->
    PostsHelper.summary(this.body)

 
# SHOW
  Template.show.isCurrentPage = ->
    return route().action == 'show'

  Template.show.post = ->
    path = route().params.path
    post = PostsHelper.findByUrl(path.join('/'))
    if post?
      post.body = _.map(post.body.split(/[\n]{2,}/), (n)->
        if n.length > 0 && n[0] != '<' && n[-1] != '>'
          "<p>#{n}</p>"
        else
          n
      ).join('\n')
      return post
    else
      RouteHelper.render404()


# ADMIN
  Template.admin.isCurrentPage = ->
    return route().action == 'admin' && isAdminUser()

  Template.admin.posts = ->
    return PostsHelper.all()

  Template.postAdmin.isValid = ->
    return PostsHelper.isValid(this)

  admin = {
    addPost: -> goto('create')

    hidePost: ->
      Posts.update(this._id, {$set: {visible: false}})

    showPost: ->
      if PostsHelper.isValid(PostsHelper.thisPost(this))
        Posts.update(this._id, {$set: {visible: true}})
      else
        window.alert("Sorry that post cannot be made visible because it is not valid")

    deletePost: ->
      if confirm("Are you sure you want to delete this post?")
        Posts.remove(this._id)

    editPost: -> goto(['edit', this.url].join('/'))
  }

  Template.admin.events({
    'click .add-action' : admin.addPost
    'click .hide-action' : admin.hidePost
    'click .show-action' : admin.showPost
    'click .delete-action' : admin.deletePost
    'click .edit-action' : admin.editPost
  })


# NEW POST

  postDataFromForm = ->
    url = $('#field-url').attr('value')
    url = RouteHelper.removeForwardSlashPrefix(url)
    post = {
      name: $('#field-name').attr('value'),
      visible: true,
      url: url,
      body: $('#field-body').attr('value'),
      created_at: new Date()
    }
    return post

  createPost = ->
    if isAdminUser()
      postData = postDataFromForm()
      validation = PostsHelper.validateCreate(postData)
      if validation.ok()
        Posts.insert(postData)
        goto(postData.url)
      else
        window.alert("Post is not valid:\n#{_.values(validation.errors).join("\n")}")
    else
      window.alert("You are not admin")
      goto('/')

  Template.create.isCurrentPage = ->
    return route().action == 'create' && isAdminUser()

  Template.create.post = ->
    return {name: 'New post', visible: false, url: '', body: ''}

  Template.create.events({
    'click .save-action': -> createPost()
    'click .discard-action': ->
      goto('admin') if confirm("Are you sure you want to discard this post?")
  })

# EDIT POST

  updatePost = (that)->
    if isAdminUser()
      postData = postDataFromForm()
      postData.url = RouteHelper.removeForwardSlashPrefix(postData.url)
      validation = PostsHelper.validateUpdate(postData)
      if validation.ok()
        Posts.update(that._id, postData)
        goto(postData.url)
      else
        window.alert("Post is no longer valid:\n#{_.values(validation.errors).join("\n")}")
    else
      window.alert("You are not admin")
      goto('/')

  Template.edit.isCurrentPage = ->
    return route().action == 'edit' && isAdminUser()

  Template.edit.post = ->
    path = route().params.path
    return PostsHelper.findByUrl(path.join('/'))

  Template.edit.events({
    'click .save-action': -> updatePost(this)
    'click .discard-action': ->
      goto('/admin') if confirm("Are you sure you want to discard edits to this post?")
  })



if Meteor.isServer
  Meteor.startup ->
    #Posts.remove({})
    if Posts.find().count() == 0
      console.log("adding posts")
      for post in POSTS
        Posts.insert(post)
    
