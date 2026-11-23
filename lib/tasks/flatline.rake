namespace :flatline do
  desc "Hash a new owner password for FLATLINE_PASSWORD_DIGEST (reads FLATLINE_PASSWORD, or asks)"
  task :password do
    require "bcrypt"
    require "io/console"

    password = ENV["FLATLINE_PASSWORD"].presence
    unless password
      abort "Run this in a terminal, or set FLATLINE_PASSWORD." unless $stdin.tty?

      password = $stdin.getpass("New password: ")
      abort "Passwords don't match." unless password == $stdin.getpass("Repeat password: ")
    end
    abort "Use at least 12 characters." if password.length < 12

    digest = BCrypt::Password.create(password)

    if ENV["FLATLINE_PASSWORD"].present?
      puts digest
    else
      puts <<~TEXT

        Put this line in the configuration file (/home/deploy/flatline/shared/flatline.env),
        replacing the old one, then restart: sudo systemctl restart flatline-web flatline-jobs

        FLATLINE_PASSWORD_DIGEST='#{digest}'
      TEXT
    end
  end
end
