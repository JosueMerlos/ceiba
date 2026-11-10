module Identity
  # Wrong email or password. ONE class for both "no such account" and "wrong password": callers cannot tell them apart,
  # so the API never reveals which emails have an account.
  class InvalidCredentials < Error; end
end
