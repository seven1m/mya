class Person
  def initialize(name, age) # name:String, age:Integer
    @name = name # @name:String
    @age = age # @age:Integer
    @score = 0 # @score:Integer
  end

  def name
    @name
  end

  def age
    @age
  end

  def score
    @score
  end

  def add_points(points) # points:Integer
    @score = @score + points
  end

  def info
    @name + ' is ' + @age.to_s + ' years old with ' + @score.to_s + ' points'
  end
end

def process_numbers
  count = 5 # count:Integer
  message = 'Count is: ' # message:String

  count = count * 2
  message = message + count.to_s

  puts message
  count
end

def add_numbers(x, y) # x:Integer, y:Integer
  puts 'Adding ' + x.to_s + ' and ' + y.to_s
  x + y
end

def greet_person(name) # name:String
  puts 'Hello, ' + name + '!'
  name
end

person = Person.new('Alice', 25)
puts person.info

person.add_points(100)
puts person.info

sum = add_numbers(10, 20)
puts 'Sum: ' + sum.to_s

greeting = greet_person('Bob')
puts 'Greeted: ' + greeting
