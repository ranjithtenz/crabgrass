require File.dirname(__FILE__) + '/../../test_helper'
require 'discussion_page_controller'

# Re-raise errors caught by the controller.
class DiscussionPageController; def rescue_action(e) raise e end; end

class Tool::DiscussionPageControllerTest < Test::Unit::TestCase
  fixtures :pages, :users, :user_participations

  def setup
    @controller = DiscussionPageController.new
    @request    = ActionController::TestRequest.new
    @request.host = "localhost"
    @response   = ActionController::TestResponse.new
  end

  def test_create_and_show
    login_as :orange
    
    assert_no_difference 'Page.count' do
      get :create, :id => DiscussionPage.param_id
      assert_response :success
    end
  
    assert_difference 'DiscussionPage.count' do
      post :create, :id => DiscussionPage.param_id, :page => { :title => 'test discussion', :tag_list => 'humma, yumma' }
    end
    page = assigns(:page)
    assert page
    assert page.tag_list.include?('humma')
    assert Page.find(page.id).tag_list.include?('humma')
    assert_response :redirect

    get :show
    assert_response :success
  end

end
