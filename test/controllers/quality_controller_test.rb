require "test_helper"

class QualityControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get quality_index_url
    assert_response :success
  end
end
