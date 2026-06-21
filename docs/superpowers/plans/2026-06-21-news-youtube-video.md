# News YouTube Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one editable YouTube URL per News post and keep the existing consent-protected public embed.

**Architecture:** Keep the existing `blog_posts.youtube_video_urls` JSONB column as storage, but expose a single editorial `youtube_video_url` API on `BlogPost`. The backend posts one field, the model normalizes it into at most one embed URL, and the public presenter reads the stored array as before.

**Tech Stack:** Rails 8.1, Active Record, ERB, Minitest, existing consent media partial.

---

### Task 1: Model API

**Files:**
- Modify: `app/models/blog_post.rb`
- Test: `test/models/blog_post_test.rb`

- [x] **Step 1: Write the failing model tests**

Add tests that assign one regular YouTube URL through `youtube_video_url`, assert `youtube_video_urls` contains one embed URL, assert the getter returns that URL, and assert blank assignment clears the array.

```ruby
test "youtube video url stores one normalized embed url" do
  blog_post = BlogPost.new(
    title: "Video News",
    teaser: "Teaser",
    body: "<div>Inhalt</div>",
    author: @author,
    status: "draft",
    youtube_video_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  )

  assert_predicate blog_post, :valid?
  assert_equal [ "https://www.youtube.com/embed/dQw4w9WgXcQ" ], blog_post.youtube_video_urls
  assert_equal "https://www.youtube.com/embed/dQw4w9WgXcQ", blog_post.youtube_video_url
end

test "blank youtube video url clears stored videos" do
  blog_post = BlogPost.new(
    title: "Video News",
    teaser: "Teaser",
    body: "<div>Inhalt</div>",
    author: @author,
    status: "draft",
    youtube_video_urls: [ "https://www.youtube.com/embed/dQw4w9WgXcQ" ]
  )

  blog_post.youtube_video_url = ""

  assert_empty blog_post.youtube_video_urls
  assert_nil blog_post.youtube_video_url
end
```

- [x] **Step 2: Run the model tests to verify failure**

Run: `mise exec -- bin/rails test test/models/blog_post_test.rb`

Expected: failure because `youtube_video_url` is unknown or not implemented.

- [x] **Step 3: Implement the model API**

Add public methods to `BlogPost` before the private section:

```ruby
def youtube_video_url
  youtube_video_urls.first
end

def youtube_video_url=(value)
  self.youtube_video_urls = [ value ]
end
```

The existing `normalize_attributes` callback will normalize, reject invalid links, and keep one URL.

- [x] **Step 4: Run the model tests to verify pass**

Run: `mise exec -- bin/rails test test/models/blog_post_test.rb`

Expected: all tests pass.

### Task 2: Backend Editing

**Files:**
- Modify: `app/controllers/backend/blog_posts_controller.rb`
- Modify: `app/views/backend/blog_posts/_news_fields.html.erb`
- Test: `test/controllers/backend/blog_posts_controller_test.rb`

- [x] **Step 1: Write the failing controller/view tests**

Add assertions that the editor renders one YouTube URL field and that updating it stores one normalized embed URL.

```ruby
assert_select "#blog-editor-panel-news input[name='blog_post[youtube_video_url]'][form='editor_form_blog_post_#{blog_post.id}']", count: 1
```

Add an integration test:

```ruby
test "editor can save one youtube video url for a blog post" do
  sign_in_as(@editor)
  blog_post = create_blog_post(author: @editor, status: "draft")

  patch backend_blog_post_url(blog_post), params: {
    blog_post: {
      title: blog_post.title,
      teaser: blog_post.teaser,
      slug: blog_post.slug,
      body: "<div>Mit Video.</div>",
      youtube_video_url: "https://youtu.be/dQw4w9WgXcQ"
    },
    publication_action: "save"
  }

  assert_redirected_to backend_blog_posts_url(blog_post_id: blog_post.id)
  assert_equal [ "https://www.youtube.com/embed/dQw4w9WgXcQ" ], blog_post.reload.youtube_video_urls
end
```

- [x] **Step 2: Run the backend controller tests to verify failure**

Run: `mise exec -- bin/rails test test/controllers/backend/blog_posts_controller_test.rb`

Expected: failure because the field is missing and the parameter is not permitted.

- [x] **Step 3: Permit and render the field**

Add `:youtube_video_url` to `blog_post_params`.

Add this field in `app/views/backend/blog_posts/_news_fields.html.erb` after `published_at`:

```erb
<div>
  <%= form.label :youtube_video_url, "YouTube-URL", class: "form-label" %>
  <%= form.url_field :youtube_video_url,
                     class: "form-input",
                     placeholder: "https://www.youtube.com/watch?v=..." %>
  <p class="blog-editor-hint">Optional. Pro News-Beitrag wird ein YouTube-Video angezeigt.</p>
</div>
```

- [x] **Step 4: Run the backend controller tests to verify pass**

Run: `mise exec -- bin/rails test test/controllers/backend/blog_posts_controller_test.rb`

Expected: all tests pass.

### Task 3: Public Coverage And Checks

**Files:**
- Modify if needed: `test/controllers/public/news_controller_test.rb`
- No README change unless implementation introduces setup, operations, architecture, dependency, or troubleshooting changes.

- [x] **Step 1: Keep or adjust public test coverage**

If the existing public test still uses `youtube_video_urls`, leave it because it covers imported data and stored state. If the model API change requires an update, set `youtube_video_url: "https://youtu.be/dQw4w9WgXcQ"` in the test helper call.

- [x] **Step 2: Run focused tests**

Run:

```bash
mise exec -- bin/rails test test/models/blog_post_test.rb test/controllers/backend/blog_posts_controller_test.rb test/controllers/public/news_controller_test.rb
```

Expected: all tests pass.

- [x] **Step 3: Run RuboCop on affected Ruby files**

Run:

```bash
mise exec -- bundle exec rubocop app/models/blog_post.rb app/controllers/backend/blog_posts_controller.rb test/models/blog_post_test.rb test/controllers/backend/blog_posts_controller_test.rb test/controllers/public/news_controller_test.rb
```

Expected: no offenses.

- [x] **Step 4: Confirm README decision**

Check that no setup, operations, architecture, dependency, or troubleshooting behavior changed. If true, leave `README.md` unchanged and mention that in the final response.
