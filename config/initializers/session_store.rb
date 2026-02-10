Rails.application.config.session_store :cache_store,
  key: "_online_learning_eval_session",
  expire_after: 2.hours
