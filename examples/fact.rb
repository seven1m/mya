def fact(n, result)
  if n == 0
    result
  else
    fact(n - 1, result * n)
  end
end

puts fact(10, 1).to_s
