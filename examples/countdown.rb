def countdown(n)
  while n > 0
    puts n.to_s
    n = n - 1
  end
  puts 'Done!'
end

countdown(5)
